"""Miniflux MCP server.

Thin MCP wrapper over the Miniflux REST API (v1). Auth: bearer token at
the MCP layer (sops-managed). The MCP-to-Miniflux auth uses an X-Auth-Token
header (Miniflux's own personal API key, also from sops).
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from contextlib import asynccontextmanager
from importlib.metadata import PackageNotFoundError, version as _pkg_version
from typing import Any

try:
    __version__ = _pkg_version("miniflux-mcp")
except PackageNotFoundError:
    __version__ = "0.0.0-dev"

import httpx
import uvicorn
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

log = logging.getLogger("miniflux_mcp")


class Config:
    def __init__(self) -> None:
        self.bind_ip = os.environ.get("MINIFLUX_MCP_BIND_IP", "auto")
        self.port = int(os.environ.get("MINIFLUX_MCP_PORT", "4284"))
        self.tokens_file = os.environ["MINIFLUX_MCP_TOKENS_FILE"]
        self.miniflux_url = os.environ["MINIFLUX_MCP_MINIFLUX_URL"].rstrip("/")
        self.miniflux_token = os.environ["MINIFLUX_MCP_MINIFLUX_TOKEN"]

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


# ── auth middleware ─────────────────────────────────────────────────────────

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


# ── miniflux API client ─────────────────────────────────────────────────────

async def miniflux(
    method: str,
    path: str,
    *,
    params: dict[str, Any] | None = None,
    json_body: Any = None,
) -> Any:
    """Call the Miniflux REST API. Path is relative to /v1/."""
    assert CFG is not None
    url = f"{CFG.miniflux_url}/v1/{path.lstrip('/')}"
    headers = {"X-Auth-Token": CFG.miniflux_token}
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.request(method, url, headers=headers, params=params, json=json_body)
    if r.status_code >= 400:
        # Surface a structured error to the caller, but never the auth token.
        raise RuntimeError(f"miniflux {method} {path} -> {r.status_code}: {r.text[:500]}")
    if not r.content:
        return None
    return r.json()


# ── MCP server ──────────────────────────────────────────────────────────────

mcp = FastMCP("miniflux")


@mcp.tool()
async def me() -> dict[str, Any]:
    """Return the current Miniflux user (whoever owns the configured API key)."""
    return await miniflux("GET", "/me")


@mcp.tool()
async def feed_list(category_id: int | None = None) -> list[dict[str, Any]]:
    """List subscribed feeds. Optionally filter to a specific category."""
    if category_id is not None:
        return await miniflux("GET", f"/categories/{category_id}/feeds")
    return await miniflux("GET", "/feeds")


@mcp.tool()
async def feed_get(feed_id: int) -> dict[str, Any]:
    """Get a single feed by id."""
    return await miniflux("GET", f"/feeds/{feed_id}")


@mcp.tool()
async def category_list() -> list[dict[str, Any]]:
    """List all feed categories on the account."""
    return await miniflux("GET", "/categories")


@mcp.tool()
async def category_create(title: str) -> dict[str, Any]:
    """Create a new category. Miniflux rejects duplicate titles with HTTP 400."""
    return await miniflux("POST", "/categories", json_body={"title": title})


@mcp.tool()
async def category_delete(category_id: int) -> dict[str, Any]:
    """Delete a category. Feeds in it are reassigned to the default category."""
    await miniflux("DELETE", f"/categories/{category_id}")
    return {"category_id": category_id, "deleted": True}


@mcp.tool()
async def feed_discover(url: str) -> list[dict[str, Any]]:
    """Discover feeds reachable from a homepage URL. Returns candidates with
    {url, title, type} — pick one and pass its `url` to `feed_add`. Useful when
    you only have a site URL (e.g. https://example.com) and need the feed URL."""
    return await miniflux("POST", "/discover", json_body={"url": url})


@mcp.tool()
async def feed_add(feed_url: str, category_id: int | None = None) -> dict[str, Any]:
    """Subscribe to a feed by its direct feed URL (Atom/RSS/JSON). When
    `category_id` is omitted Miniflux files the feed under the default category.
    Returns `{feed_id}` on success; raises on duplicates (Miniflux refuses to
    re-subscribe to an already-tracked URL)."""
    body: dict[str, Any] = {"feed_url": feed_url}
    if category_id is not None:
        body["category_id"] = category_id
    return await miniflux("POST", "/feeds", json_body=body)


@mcp.tool()
async def feed_delete(feed_id: int) -> dict[str, Any]:
    """Unsubscribe from a feed permanently. Removes the feed and all its
    entries from the account."""
    await miniflux("DELETE", f"/feeds/{feed_id}")
    return {"feed_id": feed_id, "deleted": True}


@mcp.tool()
async def entry_list(
    status: str | None = None,
    feed_id: int | None = None,
    category_id: int | None = None,
    search: str | None = None,
    starred: bool | None = None,
    limit: int = 50,
    offset: int = 0,
    order: str = "published_at",
    direction: str = "desc",
) -> dict[str, Any]:
    """List entries. By default returns the 50 most recent across all feeds.

    Filters (combinable):
    - `status`: 'unread' | 'read' | 'removed'
    - `feed_id`: restrict to one feed
    - `category_id`: restrict to one category
    - `search`: substring search across title + content
    - `starred`: True to include only starred entries
    Returns `{total, entries: [...]}`. Each entry has id, title, url,
    published_at, content (HTML), feed, status, starred.
    """
    params: dict[str, Any] = {"limit": limit, "offset": offset, "order": order, "direction": direction}
    if status is not None:
        params["status"] = status
    if search is not None:
        params["search"] = search
    if starred is not None:
        params["starred"] = "true" if starred else "false"
    if feed_id is not None:
        return await miniflux("GET", f"/feeds/{feed_id}/entries", params=params)
    if category_id is not None:
        return await miniflux("GET", f"/categories/{category_id}/entries", params=params)
    return await miniflux("GET", "/entries", params=params)


@mcp.tool()
async def entry_get(entry_id: int) -> dict[str, Any]:
    """Fetch a single entry by id, with full content."""
    return await miniflux("GET", f"/entries/{entry_id}")


@mcp.tool()
async def entry_mark_read(entry_ids: list[int]) -> dict[str, Any]:
    """Mark one or more entries as read."""
    await miniflux("PUT", "/entries", json_body={"entry_ids": entry_ids, "status": "read"})
    return {"updated": entry_ids, "status": "read"}


@mcp.tool()
async def entry_mark_unread(entry_ids: list[int]) -> dict[str, Any]:
    """Mark one or more entries as unread."""
    await miniflux("PUT", "/entries", json_body={"entry_ids": entry_ids, "status": "unread"})
    return {"updated": entry_ids, "status": "unread"}


@mcp.tool()
async def entry_star(entry_id: int) -> dict[str, Any]:
    """Toggle star on an entry (Miniflux's star endpoint is a toggle)."""
    await miniflux("PUT", f"/entries/{entry_id}/bookmark")
    return {"entry_id": entry_id, "starred": "toggled"}


@mcp.tool()
async def feed_refresh(feed_id: int) -> dict[str, Any]:
    """Force-refresh a feed (fetch immediately, bypassing the scheduler)."""
    await miniflux("PUT", f"/feeds/{feed_id}/refresh")
    return {"feed_id": feed_id, "refreshed": True}


# ── /version (bearer-required) ──────────────────────────────────────────────

async def version_route(_request: Request) -> JSONResponse:
    return JSONResponse({"name": "miniflux-mcp", "version": __version__})


# ── /health (no auth) ───────────────────────────────────────────────────────

async def health(_request: Request) -> JSONResponse:
    assert CFG is not None
    ok = False
    err: dict[str, str] = {}
    user_info: dict[str, Any] | None = None
    try:
        user_info = await miniflux("GET", "/me")
        ok = True
    except Exception as e:  # noqa: BLE001
        err["miniflux"] = repr(e)
    return JSONResponse(
        {
            "status": "ok" if ok else "degraded",
            "miniflux_url": CFG.miniflux_url,
            "user": (user_info or {}).get("username"),
            **({"errors": err} if err else {}),
        }
    )


# ── lifespan + main ────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(_app: Starlette):
    async with mcp.session_manager.run():
        log.info("miniflux-mcp ready (url=%s)", CFG.miniflux_url if CFG else "?")
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
        print(f"miniflux-mcp {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("MINIFLUX_MCP_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting miniflux-mcp version %s on %s:%d (miniflux=%s) with %d client tokens",
        __version__, bind_ip, CFG.port, CFG.miniflux_url, len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
