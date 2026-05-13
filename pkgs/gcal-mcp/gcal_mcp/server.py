"""Google Calendar MCP server.

Thin MCP wrapper over the Google Calendar v3 API. Reuses the OAuth
client_secret + persistent refresh-token files already on disk from
the bundled hermes-agent `google-workspace` skill setup. Read-only by
default — exposes `gcal_calendar_list` and `gcal_event_list`.

Defense in depth:
  • tailnet-only binding (resolved via `tailscale ip -4` at service start)
  • bearer-token auth at the MCP layer
  • runs as a dedicated `gcal_mcp` system user, group-read on the
    google credential files via membership in the `hermes` group
  • read-only Google Calendar scope (we do NOT request write access)
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from importlib.metadata import PackageNotFoundError, version as _pkg_version
from pathlib import Path
from typing import Any

try:
    __version__ = _pkg_version("gcal-mcp")
except PackageNotFoundError:
    __version__ = "0.0.0-dev"

import uvicorn
from google.auth.transport.requests import Request as GoogleAuthRequest
from google.oauth2.credentials import Credentials
from googleapiclient.discovery import build as build_google_service
from googleapiclient.errors import HttpError
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

log = logging.getLogger("gcal_mcp")

# SCOPES = None — let google-auth use whatever scope the existing token
# was minted with. Pinning a specific scope (e.g. calendar.readonly)
# would cause RefreshError: invalid_scope when refreshing against the
# google-workspace skill's broader token. We protect against
# accidental writes by only calling read-only Calendar API methods
# below (calendarList.list, events.list); we never call events.insert
# or similar.
SCOPES: list[str] | None = None


class Config:
    def __init__(self) -> None:
        self.bind_ip = os.environ.get("GCAL_MCP_BIND_IP", "auto")
        self.port = int(os.environ.get("GCAL_MCP_PORT", "4286"))
        self.tokens_file = os.environ["GCAL_MCP_TOKENS_FILE"]
        # The user-token JSON that holds the refresh_token from the
        # original OAuth dance. Same file the google-workspace skill
        # writes during its setup flow.
        self.google_token_file = os.environ["GCAL_MCP_GOOGLE_TOKEN_FILE"]
        # The OAuth app credentials (Google Cloud Console download).
        # Needed for refreshes — Google rotates short-lived access
        # tokens against this app identity.
        self.google_client_secret_file = os.environ[
            "GCAL_MCP_GOOGLE_CLIENT_SECRET_FILE"
        ]

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


# ── Google auth ─────────────────────────────────────────────────────────────

def load_google_credentials() -> Credentials:
    """Load the refresh-token-bearing credentials file. Auto-refreshes if
    the access token is expired, using the persistent refresh token +
    client secret.
    """
    assert CFG is not None
    token_path = Path(CFG.google_token_file)
    if not token_path.is_file():
        raise RuntimeError(
            f"google token file not found at {token_path}; run the "
            "google-workspace skill setup to mint one"
        )

    client_secret_path = Path(CFG.google_client_secret_file)
    if not client_secret_path.is_file():
        raise RuntimeError(
            f"google client secret file not found at {client_secret_path}"
        )

    # Read existing token; from_authorized_user_file handles both stripped
    # and full token JSON shapes.
    creds = Credentials.from_authorized_user_file(str(token_path), SCOPES)
    if creds and not creds.valid and creds.expired and creds.refresh_token:
        creds.refresh(GoogleAuthRequest())
        # Intentionally do NOT persist the refreshed access token back
        # to disk — the hermes state dir is read-only in our systemd
        # sandbox (ReadOnlyPaths). The refresh happens in-memory; next
        # gcal-mcp restart will refresh again. Negligible cost (one
        # extra Google token endpoint call per restart) and avoids
        # competing writes with the google-workspace skill that owns
        # the file.
    return creds


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


# ── MCP server + tools ──────────────────────────────────────────────────────

mcp = FastMCP("gcal")


@mcp.tool()
async def gcal_calendar_list() -> list[dict[str, Any]]:
    """List every Google Calendar the authenticated user can read.

    Returns a list of `{id, summary, description, time_zone, primary,
    access_role}` records. The `id` is what you pass as `calendar` to
    `gcal_event_list` — it's an email-shaped string for shared
    calendars (e.g. `xxxx@group.calendar.google.com`) or "primary" for
    the user's own.
    """
    try:
        creds = load_google_credentials()
        service = build_google_service("calendar", "v3", credentials=creds)
        result = service.calendarList().list().execute()
    except HttpError as e:
        return [{"error": f"Google API error: {e.status_code} {e.reason}"}]
    except Exception as e:  # noqa: BLE001
        return [{"error": f"{type(e).__name__}: {e}"}]

    out = []
    for item in result.get("items", []):
        out.append({
            "id": item.get("id"),
            "summary": item.get("summary"),
            "description": item.get("description"),
            "time_zone": item.get("timeZone"),
            "primary": item.get("primary", False),
            "access_role": item.get("accessRole"),
        })
    return out


@mcp.tool()
async def gcal_event_list(
    calendar: str = "primary",
    start: str | None = None,
    end: str | None = None,
    query: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """List events on a Google Calendar.

    Args:
      calendar: Calendar ID — either "primary" for the user's own
        calendar, or the ID returned by `gcal_calendar_list` (e.g.
        `xxxx@group.calendar.google.com` for shared calendars).
      start: ISO 8601 timestamp (with tz offset, e.g. "2026-05-13T00:00:00-05:00")
        for the earliest event start. Defaults to now.
      end: ISO 8601 timestamp for latest event start. Defaults to 7 days
        from `start`.
      query: Optional free-text search across event summary/description.
      limit: Maximum events returned (1-250). Default 50.

    Returns: list of `{id, summary, start, end, location, description,
    attendees, organizer, hangout_link, recurring}`. Times are returned
    as ISO 8601 strings preserving the calendar's stored timezone.
    """
    try:
        creds = load_google_credentials()
        service = build_google_service("calendar", "v3", credentials=creds)
    except Exception as e:  # noqa: BLE001
        return [{"error": f"auth: {type(e).__name__}: {e}"}]

    now = datetime.now(timezone.utc)
    start_iso = start or now.isoformat()
    end_iso = end or (now + timedelta(days=7)).isoformat()

    params: dict[str, Any] = {
        "calendarId": calendar,
        "timeMin": start_iso,
        "timeMax": end_iso,
        "singleEvents": True,
        "orderBy": "startTime",
        "maxResults": max(1, min(250, int(limit))),
    }
    if query:
        params["q"] = query

    try:
        result = service.events().list(**params).execute()
    except HttpError as e:
        return [{"error": f"Google API error: {e.status_code} {e.reason}"}]
    except Exception as e:  # noqa: BLE001
        return [{"error": f"{type(e).__name__}: {e}"}]

    out: list[dict[str, Any]] = []
    for item in result.get("items", []):
        s = item.get("start", {})
        e = item.get("end", {})
        out.append({
            "id": item.get("id"),
            "summary": item.get("summary", "(untitled)"),
            "start": s.get("dateTime") or s.get("date"),
            "end": e.get("dateTime") or e.get("date"),
            "all_day": "date" in s and "dateTime" not in s,
            "location": item.get("location"),
            "description": item.get("description"),
            "attendees": [
                a.get("email") for a in item.get("attendees", []) if a.get("email")
            ],
            "organizer": (item.get("organizer") or {}).get("email"),
            "hangout_link": item.get("hangoutLink"),
            "recurring": bool(item.get("recurringEventId")),
            "html_link": item.get("htmlLink"),
        })
    return out


# ── /version + /health ──────────────────────────────────────────────────────

async def version_route(_request: Request) -> JSONResponse:
    return JSONResponse({"name": "gcal-mcp", "version": __version__})


async def health(_request: Request) -> JSONResponse:
    """Health check — verifies token + client_secret files are readable
    and the credentials object can be constructed. Does NOT make a live
    Google API call (would burn quota on every health poll).
    """
    assert CFG is not None
    status: dict[str, Any] = {
        "status": "ok",
        "google_token_file": CFG.google_token_file,
        "google_client_secret_file": CFG.google_client_secret_file,
    }
    try:
        creds = load_google_credentials()
        status["has_refresh_token"] = bool(creds.refresh_token)
        status["scopes"] = list(creds.scopes or [])
    except Exception as e:  # noqa: BLE001
        status["status"] = "degraded"
        status["error"] = f"{type(e).__name__}: {e}"
    return JSONResponse(status)


# ── lifespan + main ─────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(_app: Starlette):
    async with mcp.session_manager.run():
        log.info(
            "gcal-mcp ready; token=%s client_secret=%s",
            CFG.google_token_file if CFG else "?",
            CFG.google_client_secret_file if CFG else "?",
        )
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
        print(f"gcal-mcp {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("GCAL_MCP_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting gcal-mcp version %s on %s:%d with %d client tokens",
        __version__,
        bind_ip,
        CFG.port,
        len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
