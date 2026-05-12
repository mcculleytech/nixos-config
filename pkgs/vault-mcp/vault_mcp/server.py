"""Vault MCP server.

Exposes read/write/list/search tools over an on-disk Obsidian vault. Lives
alongside an obsidian-headless daemon that keeps the directory in sync with
Obsidian Sync, but does not depend on it — operates directly on the file
tree.

Defense in depth: tailnet-only binding, bearer-token auth, and per-call path
sanitization that refuses anything resolving outside the vault root.
"""

from __future__ import annotations

import json
import logging
import os
import re
import subprocess
import sys
from contextlib import asynccontextmanager
from importlib.metadata import PackageNotFoundError, version as _pkg_version
from pathlib import Path
from typing import Any

try:
    __version__ = _pkg_version("vault-mcp")
except PackageNotFoundError:
    __version__ = "0.0.0-dev"

import uvicorn
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

log = logging.getLogger("vault_mcp")

# Files/dirs the server never touches even if asked. .obsidian holds the
# vault's app config + sync state; we deliberately don't let agents poke it.
SKIP_PREFIXES = (".obsidian", ".trash", ".git")
TEXT_EXTENSIONS = (".md", ".canvas", ".txt")
FRONTMATTER_RE = re.compile(r"^---\n(.*?)\n---\n", re.DOTALL)


class Config:
    def __init__(self) -> None:
        self.bind_ip = os.environ.get("VAULT_MCP_BIND_IP", "auto")
        self.port = int(os.environ.get("VAULT_MCP_PORT", "4281"))
        self.vault_root = Path(os.environ["VAULT_MCP_ROOT"]).resolve()
        self.tokens_file = os.environ["VAULT_MCP_TOKENS_FILE"]
        self.max_read_bytes = int(os.environ.get("VAULT_MCP_MAX_READ_BYTES", "5242880"))  # 5 MiB
        if not self.vault_root.is_dir():
            raise SystemExit(f"VAULT_MCP_ROOT={self.vault_root} is not a directory")

    def resolve_bind_ip(self) -> str:
        if self.bind_ip != "auto":
            return self.bind_ip
        r = subprocess.run(
            ["tailscale", "ip", "-4"], capture_output=True, text=True, check=True
        )
        return r.stdout.strip().splitlines()[0]


def load_tokens(path: str) -> dict[str, str]:
    with open(path) as f:
        raw = json.load(f)
    tokens = raw.get("tokens", raw)
    if not isinstance(tokens, dict) or not tokens:
        raise SystemExit(f"{path}: expected non-empty token map")
    return {tok: client for client, tok in tokens.items()}


CFG: Config | None = None
TOKENS_BY_HEX: dict[str, str] = {}


# ── path safety ──────────────────────────────────────────────────────────────

def safe_join(rel: str) -> Path:
    """Resolve `rel` under the vault root, refusing anything that escapes.

    Rejects: absolute paths, paths whose resolved form leaves the vault,
    symlinks that escape, .obsidian/.trash/.git locations.
    """
    assert CFG is not None
    rel = rel.lstrip("/")
    candidate = (CFG.vault_root / rel).resolve()
    try:
        candidate.relative_to(CFG.vault_root)
    except ValueError as e:
        raise ValueError(f"path '{rel}' escapes the vault root") from e
    parts = candidate.relative_to(CFG.vault_root).parts
    if parts and parts[0] in SKIP_PREFIXES:
        raise ValueError(f"path '{rel}' targets a protected directory ({parts[0]})")
    return candidate


def iter_notes(folder: Path | None = None):
    """Yield Path objects for every text file under the vault (or a subfolder),
    skipping SKIP_PREFIXES and any other dotfiles.
    """
    assert CFG is not None
    base = folder or CFG.vault_root
    for p in base.rglob("*"):
        if not p.is_file():
            continue
        rel_parts = p.relative_to(CFG.vault_root).parts
        if any(part.startswith(".") for part in rel_parts):
            continue
        if any(rel_parts[0] == sp for sp in SKIP_PREFIXES):
            continue
        if p.suffix.lower() in TEXT_EXTENSIONS:
            yield p


def parse_frontmatter(content: str) -> tuple[dict[str, Any], str]:
    """Best-effort YAML-like frontmatter parse. Returns (metadata, body).
    Avoids a YAML dependency by treating the frontmatter as simple key:value
    pairs; nested structures are returned as raw strings.
    """
    m = FRONTMATTER_RE.match(content)
    if not m:
        return {}, content
    raw = m.group(1)
    meta: dict[str, Any] = {}
    for line in raw.splitlines():
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        meta[key.strip()] = val.strip().strip('"').strip("'")
    return meta, content[m.end():]


# ── auth middleware ───────────────────────────────────────────────────────────

class BearerAuthMiddleware(BaseHTTPMiddleware):
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


# ── MCP server + tools ────────────────────────────────────────────────────────

mcp = FastMCP("vault")


@mcp.tool()
async def vault_read(path: str) -> dict[str, Any]:
    """Read a note from the vault. Path is relative to the vault root.

    Returns `{path, content, frontmatter, size, mtime}`. Content is truncated
    if the file exceeds the server's max-read-bytes limit (default 5 MiB).
    """
    assert CFG is not None
    target = safe_join(path)
    if not target.exists():
        return {"error": f"not found: {path}"}
    if not target.is_file():
        return {"error": f"not a file: {path}"}
    stat = target.stat()
    truncated = False
    raw = target.read_bytes()
    if len(raw) > CFG.max_read_bytes:
        raw = raw[: CFG.max_read_bytes]
        truncated = True
    content = raw.decode("utf-8", errors="replace")
    fm, body = parse_frontmatter(content)
    return {
        "path": str(target.relative_to(CFG.vault_root)),
        "content": content,
        "body": body,
        "frontmatter": fm,
        "size": stat.st_size,
        "mtime": stat.st_mtime,
        "truncated": truncated,
    }


@mcp.tool()
async def vault_write(path: str, content: str, overwrite: bool = False) -> dict[str, Any]:
    """Create or overwrite a note. Refuses to overwrite an existing file unless
    `overwrite=True`. Auto-creates parent directories.

    Returns `{path, bytes_written, created}`.
    """
    target = safe_join(path)
    existed = target.exists()
    if existed and not overwrite:
        return {"error": f"file exists; pass overwrite=true to replace: {path}"}
    target.parent.mkdir(parents=True, exist_ok=True)
    data = content.encode("utf-8")
    target.write_bytes(data)
    assert CFG is not None
    return {
        "path": str(target.relative_to(CFG.vault_root)),
        "bytes_written": len(data),
        "created": not existed,
    }


@mcp.tool()
async def vault_append(path: str, content: str, separator: str = "\n") -> dict[str, Any]:
    """Append content to a note. If the file doesn't exist, creates it (no
    separator on first write). Useful for journal/log-style notes.

    Returns `{path, bytes_appended, created}`.
    """
    target = safe_join(path)
    existed = target.exists()
    target.parent.mkdir(parents=True, exist_ok=True)
    with target.open("ab") as f:
        if existed and not target.read_bytes().endswith(separator.encode("utf-8")):
            f.write(separator.encode("utf-8"))
        bytes_written = f.write(content.encode("utf-8"))
    assert CFG is not None
    return {
        "path": str(target.relative_to(CFG.vault_root)),
        "bytes_appended": bytes_written,
        "created": not existed,
    }


@mcp.tool()
async def vault_list(folder: str | None = None, limit: int = 200) -> list[dict[str, Any]]:
    """List notes in the vault (or under a subfolder). Returns up to `limit`
    entries with `{path, size, mtime}`. Excludes .obsidian/.trash/.git and
    other dotfiles.
    """
    assert CFG is not None
    base = safe_join(folder) if folder else CFG.vault_root
    out: list[dict[str, Any]] = []
    for p in iter_notes(base):
        stat = p.stat()
        out.append({
            "path": str(p.relative_to(CFG.vault_root)),
            "size": stat.st_size,
            "mtime": stat.st_mtime,
        })
        if len(out) >= limit:
            break
    out.sort(key=lambda r: r["mtime"], reverse=True)
    return out


@mcp.tool()
async def vault_search(
    query: str,
    folder: str | None = None,
    case_insensitive: bool = True,
    limit: int = 50,
    snippet_chars: int = 160,
) -> list[dict[str, Any]]:
    """Substring search across vault notes. Returns up to `limit` hits with
    `{path, line, snippet}`. For semantic search, see the agent-memory MCP
    (separate service).
    """
    assert CFG is not None
    base = safe_join(folder) if folder else CFG.vault_root
    flags = re.IGNORECASE if case_insensitive else 0
    pat = re.compile(re.escape(query), flags)
    hits: list[dict[str, Any]] = []
    for p in iter_notes(base):
        try:
            text = p.read_text(encoding="utf-8", errors="replace")
        except OSError:
            continue
        for i, line in enumerate(text.splitlines(), start=1):
            m = pat.search(line)
            if not m:
                continue
            start = max(0, m.start() - snippet_chars // 2)
            end = min(len(line), m.end() + snippet_chars // 2)
            hits.append({
                "path": str(p.relative_to(CFG.vault_root)),
                "line": i,
                "snippet": line[start:end],
            })
            if len(hits) >= limit:
                return hits
    return hits


@mcp.tool()
async def vault_metadata(path: str) -> dict[str, Any]:
    """Read a note's frontmatter and stats without returning the body.
    Useful for quick lookups."""
    assert CFG is not None
    target = safe_join(path)
    if not target.is_file():
        return {"error": f"not a file: {path}"}
    stat = target.stat()
    # Read just enough to capture the frontmatter block.
    head = target.open("rb").read(8192).decode("utf-8", errors="replace")
    fm, _ = parse_frontmatter(head)
    return {
        "path": str(target.relative_to(CFG.vault_root)),
        "size": stat.st_size,
        "mtime": stat.st_mtime,
        "frontmatter": fm,
    }


# ── /version route (bearer-required) ─────────────────────────────────────────

async def version_route(_request: Request) -> JSONResponse:
    return JSONResponse({"name": "vault-mcp", "version": __version__})


# ── /health route (no auth) ──────────────────────────────────────────────────

async def health(_request: Request) -> JSONResponse:
    assert CFG is not None
    vault_ok = CFG.vault_root.is_dir()
    note_count = 0
    try:
        # Bound the count so a huge vault doesn't make the health check slow.
        for _ in iter_notes():
            note_count += 1
            if note_count >= 1000:
                break
    except Exception as e:  # noqa: BLE001
        return JSONResponse(
            {"status": "degraded", "vault_ok": False, "error": repr(e)}
        )
    return JSONResponse({
        "status": "ok" if vault_ok else "degraded",
        "vault_ok": vault_ok,
        "vault_root": str(CFG.vault_root),
        "approx_note_count": note_count if note_count < 1000 else f"{note_count}+",
    })


# ── lifespan + main ──────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(_app: Starlette):
    async with mcp.session_manager.run():
        log.info("vault-mcp ready; vault_root=%s", CFG.vault_root if CFG else "?")
        yield


def build_app() -> Starlette:
    mcp_app = mcp.streamable_http_app()
    return Starlette(
        debug=False,
        routes=[
            Route("/health", health, methods=["GET"]),
            Route("/version", version_route, methods=["GET"]),
            Mount("/", app=mcp_app),
        ],
        middleware=[Middleware(BearerAuthMiddleware)],
        lifespan=lifespan,
    )


def main() -> None:
    if "--version" in sys.argv[1:]:
        print(f"vault-mcp {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("VAULT_MCP_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting vault-mcp version %s on %s:%d (vault=%s) with %d client tokens",
        __version__, bind_ip, CFG.port, CFG.vault_root, len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
