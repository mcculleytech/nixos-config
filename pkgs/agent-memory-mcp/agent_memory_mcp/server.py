"""Shared agent memory MCP server.

Fronts a pgvector-backed Postgres database. Exposes tools to insert, search,
update, and delete semantic memories scoped by project and tags. Embedding is
delegated to a locally-hosted Ollama instance.

Auth: bearer token via a JSON file mapping client names to hex tokens.
Binding: a specific IP (typically the host's tailnet IP), never 0.0.0.0.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from contextlib import asynccontextmanager
from typing import Any
from uuid import UUID

import httpx
import psycopg
import uvicorn
from mcp.server.fastmcp import FastMCP
from pgvector.psycopg import register_vector_async
from psycopg.rows import dict_row
from psycopg.types.json import Json
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

log = logging.getLogger("agent_memory_mcp")

EMBED_DIM = 768  # nomic-embed-text


class Config:
    """Process-wide config read once at startup from env."""

    def __init__(self) -> None:
        self.bind_ip = os.environ.get("AGENT_MEMORY_BIND_IP", "auto")
        self.port = int(os.environ.get("AGENT_MEMORY_PORT", "4280"))
        self.db_dsn = os.environ.get(
            "AGENT_MEMORY_DB_DSN",
            "postgresql:///agent_memory?host=/run/postgresql",
        )
        self.tokens_file = os.environ["AGENT_MEMORY_TOKENS_FILE"]
        self.ollama_url = os.environ.get("OLLAMA_URL", "http://127.0.0.1:11434")
        self.embed_model = os.environ.get("OLLAMA_EMBED_MODEL", "nomic-embed-text")

    def resolve_bind_ip(self) -> str:
        if self.bind_ip != "auto":
            return self.bind_ip
        result = subprocess.run(
            ["tailscale", "ip", "-4"], capture_output=True, text=True, check=True
        )
        # `tailscale ip -4` can return multiple lines (e.g. with subnet routes);
        # the first is the node's own tailnet IP.
        return result.stdout.strip().splitlines()[0]


def load_tokens(path: str) -> dict[str, str]:
    """Load {client_name: token} from JSON. Inverts to {token: client_name}."""
    with open(path) as f:
        data = json.load(f)
    raw = data.get("tokens", data)  # accept either {tokens: {...}} or flat
    if not isinstance(raw, dict) or not raw:
        raise SystemExit(f"{path}: expected non-empty token map")
    return {token: client for client, token in raw.items()}


# ── connection pool / app state ────────────────────────────────────────────────

CFG: Config | None = None
TOKENS_BY_HEX: dict[str, str] = {}
DB_POOL: psycopg.AsyncConnection | None = None  # one connection, simple


@asynccontextmanager
async def lifespan(_app: Starlette):
    """Compose our DB setup with FastMCP's session manager lifecycle.

    FastMCP requires `session_manager.run()` to be active for the lifetime of
    the streamable-HTTP app; without it, request handlers raise
    "Task group is not initialized". When mounting FastMCP under a custom
    Starlette app, we must drive that ourselves.
    """
    global DB_POOL
    assert CFG is not None
    async with mcp.session_manager.run():
        DB_POOL = await psycopg.AsyncConnection.connect(CFG.db_dsn, autocommit=True)
        await register_vector_async(DB_POOL)
        log.info("connected to %s", CFG.db_dsn)
        try:
            yield
        finally:
            await DB_POOL.close()


async def db() -> psycopg.AsyncConnection:
    if DB_POOL is None:
        raise RuntimeError("db pool not initialized")
    return DB_POOL


# ── auth middleware ───────────────────────────────────────────────────────────

class BearerAuthMiddleware(BaseHTTPMiddleware):
    """Reject requests lacking a valid bearer token. /health is exempt."""

    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/health":
            return await call_next(request)
        auth = request.headers.get("authorization", "")
        if not auth.lower().startswith("bearer "):
            return JSONResponse({"error": "missing bearer token"}, status_code=401)
        token = auth.split(" ", 1)[1].strip()
        client = TOKENS_BY_HEX.get(token)
        if client is None:
            return JSONResponse({"error": "invalid token"}, status_code=401)
        request.state.client = client
        return await call_next(request)


# ── embedding helper ──────────────────────────────────────────────────────────

async def embed(text: str) -> list[float]:
    assert CFG is not None
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.post(
            f"{CFG.ollama_url}/api/embeddings",
            json={"model": CFG.embed_model, "prompt": text},
        )
        if r.status_code != 200:
            raise RuntimeError(
                f"Ollama embedding failed ({r.status_code}): {r.text}. "
                f"Try: `ollama pull {CFG.embed_model}` on the host running Ollama."
            )
        data = r.json()
        vec = data.get("embedding")
        if not isinstance(vec, list) or len(vec) != EMBED_DIM:
            raise RuntimeError(
                f"Ollama returned unexpected embedding shape: len={len(vec) if isinstance(vec, list) else 'n/a'}; expected {EMBED_DIM}"
            )
        return vec


# ── project resolution ────────────────────────────────────────────────────────

async def resolve_project_id(conn: psycopg.AsyncConnection, name: str | None) -> str | None:
    if name is None:
        return None
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute("SELECT id FROM projects WHERE name = %s", (name,))
        row = await cur.fetchone()
        if row:
            return str(row["id"])
        await cur.execute(
            "INSERT INTO projects (name) VALUES (%s) RETURNING id", (name,)
        )
        row = await cur.fetchone()
        assert row is not None
        return str(row["id"])


# ── MCP server + tools ────────────────────────────────────────────────────────

mcp = FastMCP("agent-memory")


@mcp.tool()
async def memory_search(
    query: str,
    project: str | None = None,
    tags: list[str] | None = None,
    limit: int = 10,
) -> list[dict[str, Any]]:
    """Semantic search across memories. Returns up to `limit` rows sorted by
    cosine distance (smallest first).

    - `project`: if set, restrict to memories whose `project.name` matches.
    - `tags`: if set, restrict to memories that share at least one tag with the list.
    """
    conn = await db()
    vec = await embed(query)
    where: list[str] = []
    params: list[Any] = [vec]  # first %s is for the similarity SELECT
    if project is not None:
        where.append("p.name = %s")
        params.append(project)
    if tags:
        where.append("m.tags && %s")
        params.append(list(tags))
    params.extend([vec, limit])  # for ORDER BY ... LIMIT
    where_sql = ("WHERE " + " AND ".join(where)) if where else ""
    # `::vector` casts are required: with the `<=>` operator psycopg can't
    # infer the parameter type and defaults to double precision[], which
    # doesn't match `vector` — the operator resolution fails at parse time.
    sql = f"""
        SELECT m.id, m.content, m.source, m.tags, m.metadata, m.created_at,
               p.name AS project,
               1 - (m.embedding <=> %s::vector) AS similarity
        FROM memories m
        LEFT JOIN projects p ON p.id = m.project_id
        {where_sql}
        ORDER BY m.embedding <=> %s::vector
        LIMIT %s
    """
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(sql, params)
        rows = await cur.fetchall()
    return [
        {
            "id": str(r["id"]),
            "content": r["content"],
            "project": r["project"],
            "source": r["source"],
            "tags": r["tags"],
            "metadata": r["metadata"],
            "similarity": float(r["similarity"]),
            "created_at": r["created_at"].isoformat(),
        }
        for r in rows
    ]


@mcp.tool()
async def memory_insert(
    content: str,
    project: str | None = None,
    source: str | None = None,
    tags: list[str] | None = None,
    metadata: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Embed `content` and insert as a new memory. Returns the new row's id.

    If `project` is set and the project doesn't exist, it's created on the fly.
    """
    conn = await db()
    vec = await embed(content)
    project_id = await resolve_project_id(conn, project)
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(
            """
            INSERT INTO memories (content, embedding, source, project_id, tags, metadata)
            VALUES (%s, %s, %s, %s, %s, %s)
            RETURNING id, created_at
            """,
            (
                content,
                vec,
                source,
                project_id,
                list(tags or []),
                Json(metadata or {}),
            ),
        )
        row = await cur.fetchone()
    assert row is not None
    return {"id": str(row["id"]), "created_at": row["created_at"].isoformat()}


@mcp.tool()
async def memory_update(
    id: str,
    content: str | None = None,
    tags: list[str] | None = None,
    metadata: dict[str, Any] | None = None,
) -> bool:
    """Update one or more fields on a memory. If `content` is updated, the
    embedding is re-computed. Returns True iff a row was modified.
    """
    try:
        uid = UUID(id)
    except ValueError:
        return False
    conn = await db()
    sets: list[str] = []
    params: list[Any] = []
    if content is not None:
        vec = await embed(content)
        sets.append("content = %s")
        params.append(content)
        sets.append("embedding = %s")
        params.append(vec)
    if tags is not None:
        sets.append("tags = %s")
        params.append(list(tags))
    if metadata is not None:
        sets.append("metadata = %s")
        params.append(Json(metadata))
    if not sets:
        return False
    sets.append("updated_at = now()")
    params.append(str(uid))
    async with conn.cursor() as cur:
        await cur.execute(
            f"UPDATE memories SET {', '.join(sets)} WHERE id = %s", params
        )
        return cur.rowcount > 0


@mcp.tool()
async def memory_delete(id: str) -> bool:
    """Delete a memory by id. Returns True iff a row was removed."""
    try:
        uid = UUID(id)
    except ValueError:
        return False
    conn = await db()
    async with conn.cursor() as cur:
        await cur.execute("DELETE FROM memories WHERE id = %s", (str(uid),))
        return cur.rowcount > 0


@mcp.tool()
async def project_list() -> list[dict[str, Any]]:
    """List all projects."""
    conn = await db()
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(
            "SELECT id, name, description, created_at FROM projects ORDER BY name"
        )
        rows = await cur.fetchall()
    return [
        {
            "id": str(r["id"]),
            "name": r["name"],
            "description": r["description"],
            "created_at": r["created_at"].isoformat(),
        }
        for r in rows
    ]


@mcp.tool()
async def project_delete(name: str) -> dict[str, Any]:
    """Delete a project by name. Memories that referenced it have their
    project_id set to NULL (per the FK ON DELETE SET NULL). Returns
    `{deleted, orphaned_memories}` where orphaned_memories is how many
    memories were detached.
    """
    conn = await db()
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(
            "SELECT count(*) AS n FROM memories WHERE project_id = (SELECT id FROM projects WHERE name = %s)",
            (name,),
        )
        row = await cur.fetchone()
        orphaned = int(row["n"]) if row else 0
        await cur.execute("DELETE FROM projects WHERE name = %s", (name,))
        deleted = cur.rowcount > 0
    return {"deleted": deleted, "orphaned_memories": orphaned}


@mcp.tool()
async def project_create(name: str, description: str | None = None) -> dict[str, Any]:
    """Create a project. If one already exists with this name, returns the existing row."""
    conn = await db()
    async with conn.cursor(row_factory=dict_row) as cur:
        await cur.execute(
            """
            INSERT INTO projects (name, description) VALUES (%s, %s)
            ON CONFLICT (name) DO UPDATE SET description = COALESCE(EXCLUDED.description, projects.description)
            RETURNING id, name, description, created_at
            """,
            (name, description),
        )
        row = await cur.fetchone()
    assert row is not None
    return {
        "id": str(row["id"]),
        "name": row["name"],
        "description": row["description"],
        "created_at": row["created_at"].isoformat(),
    }


# ── /health route (no auth) ───────────────────────────────────────────────────

async def health(_request: Request) -> JSONResponse:
    assert CFG is not None
    db_ok = False
    ollama_ok = False
    err: dict[str, str] = {}
    if DB_POOL is not None:
        try:
            async with DB_POOL.cursor() as cur:
                await cur.execute("SELECT 1")
                await cur.fetchone()
            db_ok = True
        except Exception as e:  # noqa: BLE001
            err["db"] = repr(e)
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            r = await client.get(f"{CFG.ollama_url}/api/tags")
            ollama_ok = r.status_code == 200
    except Exception as e:  # noqa: BLE001
        err["ollama"] = repr(e)
    return JSONResponse(
        {"status": "ok" if (db_ok and ollama_ok) else "degraded",
         "db_ok": db_ok, "ollama_ok": ollama_ok, **({"errors": err} if err else {})}
    )


# ── main ──────────────────────────────────────────────────────────────────────

def build_app() -> Starlette:
    """Compose the MCP streamable-http app with health route and auth middleware."""
    mcp_app = mcp.streamable_http_app()
    # Mount MCP under the root and add the /health route alongside it.
    return Starlette(
        debug=False,
        routes=[
            Route("/health", health, methods=["GET"]),
            Mount("/", app=mcp_app),
        ],
        middleware=[Middleware(BearerAuthMiddleware)],
        lifespan=lifespan,
    )


def main() -> None:
    logging.basicConfig(
        level=os.environ.get("AGENT_MEMORY_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting agent-memory-mcp on %s:%d with %d client tokens",
        bind_ip, CFG.port, len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
