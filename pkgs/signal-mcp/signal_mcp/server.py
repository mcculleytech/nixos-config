"""Outbound Signal messaging MCP server.

Wraps a local signal-cli HTTP daemon for sending messages, **with a mandatory
two-step approval gate**: every outbound message must first be queued via
`signal_send_message` (creates a pending entry) and then explicitly approved
via `signal_pending_approve` before signal-cli actually transmits it.

There is no direct-send path. This is structural, not advisory — the only
place that calls signal-cli's `send` RPC is `signal_pending_approve`, and
that only operates on rows that already exist in the pending table.

The agent (e.g., Hermes) is expected to present each pending entry to the
operator and wait for explicit human confirmation before calling approve.
"""

from __future__ import annotations

import json
import logging
import os
import sqlite3
import subprocess
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from importlib.metadata import PackageNotFoundError, version as _pkg_version
from pathlib import Path
from typing import Any

try:
    __version__ = _pkg_version("signal-mcp")
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

log = logging.getLogger("signal_mcp")


class Config:
    def __init__(self) -> None:
        self.bind_ip = os.environ.get("SIGNAL_MCP_BIND_IP", "auto")
        self.port = int(os.environ.get("SIGNAL_MCP_PORT", "4282"))
        self.tokens_file = os.environ["SIGNAL_MCP_TOKENS_FILE"]
        self.signal_http_url = os.environ.get(
            "SIGNAL_MCP_SIGNAL_HTTP_URL", "http://127.0.0.1:8088"
        )
        self.signal_account = os.environ["SIGNAL_MCP_SIGNAL_ACCOUNT"]
        self.db_path = Path(
            os.environ.get("SIGNAL_MCP_DB", "/var/lib/signal-mcp/pending.db")
        )

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


# ── persistence ──────────────────────────────────────────────────────────────

SCHEMA = """
CREATE TABLE IF NOT EXISTS pending (
  id           INTEGER PRIMARY KEY AUTOINCREMENT,
  recipient    TEXT NOT NULL,
  body         TEXT NOT NULL,
  created_at   TEXT NOT NULL,
  created_by   TEXT NOT NULL,           -- bearer-token client name
  status       TEXT NOT NULL DEFAULT 'pending',  -- pending|sent|denied
  status_at    TEXT,
  status_by    TEXT,                    -- who approved/denied
  status_note  TEXT,
  send_result  TEXT                     -- JSON from signal-cli, on send
);
"""


def db_open() -> sqlite3.Connection:
    assert CFG is not None
    CFG.db_path.parent.mkdir(parents=True, exist_ok=True)
    conn = sqlite3.connect(CFG.db_path, isolation_level=None)
    conn.row_factory = sqlite3.Row
    conn.executescript(SCHEMA)
    return conn


def row_to_dict(row: sqlite3.Row) -> dict[str, Any]:
    return {k: row[k] for k in row.keys()}


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


# ── signal-cli RPC ──────────────────────────────────────────────────────────

async def signal_cli_rpc(method: str, params: dict[str, Any]) -> dict[str, Any]:
    """Call a signal-cli JSON-RPC method, return the parsed `result` or raise.

    `params` is merged with the bot account (passed as `account` for multi-
    account daemons).
    """
    assert CFG is not None
    body = {"jsonrpc": "2.0", "id": 1, "method": method, "params": {"account": CFG.signal_account, **params}}
    async with httpx.AsyncClient(timeout=30.0) as client:
        r = await client.post(f"{CFG.signal_http_url}/api/v1/rpc", json=body)
    if r.status_code != 200:
        raise RuntimeError(f"signal-cli RPC {method} -> HTTP {r.status_code}: {r.text}")
    payload = r.json()
    if "error" in payload:
        raise RuntimeError(f"signal-cli RPC {method} error: {payload['error']}")
    return payload.get("result", {})


# ── MCP server ──────────────────────────────────────────────────────────────

mcp = FastMCP("signal")


def _client_of(request_state) -> str:
    """Helper to extract the bearer-token client name in a tool. FastMCP doesn't
    surface request state directly, so we fall back to a sentinel if missing.
    Used only for audit, not authorization."""
    try:
        return getattr(request_state, "client", "unknown")
    except Exception:
        return "unknown"


@mcp.tool()
async def signal_send_message(recipient: str, body: str) -> dict[str, Any]:
    """Queue an outbound Signal message for operator approval.

    **This never sends directly.** Returns a pending_id; the operator must
    review and explicitly call `signal_pending_approve(pending_id)` before
    the message reaches signal-cli. Agents should present the queued entry
    to the human operator and wait for an explicit "yes" before approving.

    `recipient` is an E.164 number (e.g. "+15551234567") or a Signal UUID.
    """
    if not recipient or not body:
        return {"error": "recipient and body are required"}
    conn = db_open()
    cur = conn.execute(
        "INSERT INTO pending (recipient, body, created_at, created_by) "
        "VALUES (?, ?, ?, ?)",
        (recipient, body, datetime.now(timezone.utc).isoformat(), "agent"),
    )
    pid = cur.lastrowid
    log.info("queued pending message id=%d to=%s len=%d", pid, recipient, len(body))
    return {
        "pending_id": pid,
        "status": "pending",
        "recipient": recipient,
        "body": body,
        "next_step": (
            "Show this pending entry to the operator (a human). After they "
            "explicitly confirm, call signal_pending_approve(pending_id)."
        ),
    }


@mcp.tool()
async def signal_pending_list(status: str | None = "pending", limit: int = 50) -> list[dict[str, Any]]:
    """List pending (or sent/denied) outbound messages.

    `status` filters to one of: pending (default), sent, denied, all.
    Returns rows sorted most-recent first.
    """
    conn = db_open()
    if status in (None, "all"):
        rows = conn.execute(
            "SELECT * FROM pending ORDER BY id DESC LIMIT ?", (limit,)
        ).fetchall()
    else:
        rows = conn.execute(
            "SELECT * FROM pending WHERE status = ? ORDER BY id DESC LIMIT ?",
            (status, limit),
        ).fetchall()
    return [row_to_dict(r) for r in rows]


@mcp.tool()
async def signal_pending_approve(pending_id: int) -> dict[str, Any]:
    """Approve and actually send a queued outbound message.

    **This is the only path to sending.** Call only after the operator has
    explicitly confirmed the recipient and body for this pending_id.
    """
    conn = db_open()
    row = conn.execute(
        "SELECT * FROM pending WHERE id = ?", (pending_id,)
    ).fetchone()
    if row is None:
        return {"error": f"pending_id {pending_id} not found"}
    if row["status"] != "pending":
        return {
            "error": f"pending_id {pending_id} is already {row['status']}",
            "row": row_to_dict(row),
        }
    # Hand off to signal-cli.
    try:
        result = await signal_cli_rpc(
            "send",
            {"recipient": [row["recipient"]], "message": row["body"]},
        )
    except Exception as e:  # noqa: BLE001
        log.exception("send failed for pending_id=%d", pending_id)
        return {"error": f"signal-cli send failed: {e!s}", "pending_id": pending_id}
    now = datetime.now(timezone.utc).isoformat()
    conn.execute(
        "UPDATE pending SET status='sent', status_at=?, status_by=?, send_result=? "
        "WHERE id = ?",
        (now, "operator-approved", json.dumps(result), pending_id),
    )
    log.info("sent pending_id=%d to=%s", pending_id, row["recipient"])
    return {
        "pending_id": pending_id,
        "status": "sent",
        "recipient": row["recipient"],
        "sent_at": now,
        "result": result,
    }


@mcp.tool()
async def signal_pending_deny(pending_id: int, reason: str | None = None) -> dict[str, Any]:
    """Mark a queued message as denied. Drops it; nothing is sent."""
    conn = db_open()
    cur = conn.execute(
        "UPDATE pending SET status='denied', status_at=?, status_by=?, status_note=? "
        "WHERE id = ? AND status = 'pending'",
        (
            datetime.now(timezone.utc).isoformat(),
            "operator-denied",
            reason,
            pending_id,
        ),
    )
    if cur.rowcount == 0:
        return {"error": f"pending_id {pending_id} not found or not in 'pending' state"}
    log.info("denied pending_id=%d reason=%s", pending_id, reason or "(none)")
    return {"pending_id": pending_id, "status": "denied", "reason": reason}


@mcp.tool()
async def signal_list_contacts() -> list[dict[str, Any]]:
    """List the bot account's known Signal contacts (numbers and names).

    Read-only — does not send anything. Useful for the agent to suggest a
    recipient by name and confirm the resolved E.164.
    """
    try:
        contacts = await signal_cli_rpc("listContacts", {})
    except Exception as e:  # noqa: BLE001
        return [{"error": f"signal-cli listContacts failed: {e!s}"}]
    if isinstance(contacts, list):
        return contacts
    return [contacts]


@mcp.tool()
async def signal_account() -> dict[str, Any]:
    """Return the bot's own Signal account info (number, UUID, listed identities)."""
    assert CFG is not None
    try:
        result = await signal_cli_rpc("listIdentities", {})
    except Exception as e:  # noqa: BLE001
        return {"error": f"signal-cli listIdentities failed: {e!s}"}
    return {"account": CFG.signal_account, "identities": result}


# ── /version (bearer-required) ──────────────────────────────────────────────

async def version_route(_request: Request) -> JSONResponse:
    return JSONResponse({"name": "signal-mcp", "version": __version__})


# ── /health (no auth) ───────────────────────────────────────────────────────

async def health(_request: Request) -> JSONResponse:
    assert CFG is not None
    db_ok = False
    signal_ok = False
    err: dict[str, str] = {}
    try:
        conn = db_open()
        conn.execute("SELECT 1").fetchone()
        db_ok = True
    except Exception as e:  # noqa: BLE001
        err["db"] = repr(e)
    try:
        async with httpx.AsyncClient(timeout=2.0) as client:
            r = await client.post(
                f"{CFG.signal_http_url}/api/v1/rpc",
                json={"jsonrpc": "2.0", "id": 1, "method": "listAccounts", "params": {}},
            )
            signal_ok = r.status_code == 200
    except Exception as e:  # noqa: BLE001
        err["signal"] = repr(e)
    return JSONResponse(
        {
            "status": "ok" if (db_ok and signal_ok) else "degraded",
            "db_ok": db_ok,
            "signal_ok": signal_ok,
            "account": CFG.signal_account,
            **({"errors": err} if err else {}),
        }
    )


# ── lifespan + main ─────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(_app: Starlette):
    async with mcp.session_manager.run():
        log.info("signal-mcp ready (account=%s db=%s)", CFG.signal_account if CFG else "?", CFG.db_path if CFG else "?")
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
        print(f"signal-mcp {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("SIGNAL_MCP_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting signal-mcp version %s on %s:%d (account=%s db=%s) with %d client tokens",
        __version__, bind_ip, CFG.port, CFG.signal_account, CFG.db_path, len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
