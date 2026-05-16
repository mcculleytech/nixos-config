"""Radicale CalDAV/CardDAV MCP server.

Talks to a Radicale instance over plain CalDAV/CardDAV using the Python
`caldav` library. Exposes CRUD tools for events (VEVENT), tasks (VTODO),
and contacts (VCARD), plus calendar/addressbook discovery.

Auth: bearer-token (sops-managed) protects the MCP itself. Radicale
credentials (basic-auth user + password) are sourced from env vars
populated by the sops-templated EnvironmentFile.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from contextlib import asynccontextmanager
from datetime import datetime, timezone
from importlib.metadata import PackageNotFoundError, version as _pkg_version
from typing import Any
from uuid import uuid4
from zoneinfo import ZoneInfo, ZoneInfoNotFoundError

try:
    __version__ = _pkg_version("radicale-mcp")
except PackageNotFoundError:
    __version__ = "0.0.0-dev"

import uvicorn
import vobject
from caldav import DAVClient
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

log = logging.getLogger("radicale_mcp")


class Config:
    def __init__(self) -> None:
        self.bind_ip = os.environ.get("RADICALE_MCP_BIND_IP", "auto")
        self.port = int(os.environ.get("RADICALE_MCP_PORT", "4283"))
        self.tokens_file = os.environ["RADICALE_MCP_TOKENS_FILE"]
        self.radicale_url = os.environ["RADICALE_MCP_RADICALE_URL"]
        self.radicale_user = os.environ["RADICALE_MCP_RADICALE_USER"]
        self.radicale_password = os.environ["RADICALE_MCP_RADICALE_PASSWORD"]
        # Default IANA timezone for parsing naive datetime inputs from agents.
        # Calendar apps display events in *their* local time; storing naive
        # times as UTC means a "3pm" event in Central appears at 10am Central.
        # Defaulting to the host's local zone gives intuitive behavior; agents
        # can override per-event via the `tz` parameter on event_create/update.
        self.default_tz_name = os.environ.get("RADICALE_MCP_DEFAULT_TZ", "UTC")
        try:
            self.default_tz = ZoneInfo(self.default_tz_name)
        except ZoneInfoNotFoundError as e:
            raise SystemExit(f"unknown RADICALE_MCP_DEFAULT_TZ '{self.default_tz_name}': {e!s}")

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
DAV: DAVClient | None = None


def davc() -> DAVClient:
    global DAV
    if DAV is None:
        assert CFG is not None
        DAV = DAVClient(
            url=CFG.radicale_url,
            username=CFG.radicale_user,
            password=CFG.radicale_password,
        )
    return DAV


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


# ── helpers ─────────────────────────────────────────────────────────────────

def _principal():
    return davc().principal()


def _find_calendar(name: str | None):
    """Return a calendar by display-name; if name is None, return the user's
    first calendar (raises if there are none)."""
    cals = _principal().calendars()
    if not cals:
        raise RuntimeError("no calendars found for the configured Radicale user")
    if name is None:
        return cals[0]
    for c in cals:
        # Radicale exposes display names via .name (caldav lib) or .url tail.
        if getattr(c, "name", None) == name:
            return c
        if str(c.url).rstrip("/").endswith("/" + name):
            return c
    raise RuntimeError(f"calendar '{name}' not found; available: {[c.name for c in cals]}")


def _find_addressbook(name: str | None):
    abs_ = _principal().addressbooks()
    if not abs_:
        raise RuntimeError("no addressbooks found for the configured Radicale user")
    if name is None:
        return abs_[0]
    for a in abs_:
        if getattr(a, "name", None) == name:
            return a
        if str(a.url).rstrip("/").endswith("/" + name):
            return a
    raise RuntimeError(f"addressbook '{name}' not found; available: {[a.name for a in abs_]}")


def _parse_dt(s: str, tz_name: str | None = None) -> datetime:
    """Parse an ISO-8601 datetime. Naive strings get attached to `tz_name`
    (or the configured RADICALE_MCP_DEFAULT_TZ if `tz_name` is None).

    Examples:
      '2026-05-12T15:00:00Z'         → explicit UTC
      '2026-05-12T15:00:00-05:00'    → explicit -5h offset (fixed)
      '2026-05-12T15:00:00'          → naive: attach configured default zone
                                       (e.g. America/Chicago)
    """
    try:
        dt = datetime.fromisoformat(s.replace("Z", "+00:00"))
    except ValueError as e:
        raise ValueError(f"bad ISO datetime '{s}': {e!s}") from e
    if dt.tzinfo is None:
        if tz_name is not None:
            try:
                tz = ZoneInfo(tz_name)
            except ZoneInfoNotFoundError as e:
                raise ValueError(f"unknown timezone '{tz_name}': {e!s}") from e
        else:
            assert CFG is not None
            tz = CFG.default_tz
        dt = dt.replace(tzinfo=tz)
    return dt


def _vevent_summary(event) -> dict[str, Any]:
    vc = event.vobject_instance
    ve = vc.vevent
    out: dict[str, Any] = {
        "uid": str(ve.uid.value),
        "summary": str(getattr(ve, "summary", "").value) if hasattr(ve, "summary") else "",
        "url": str(event.url),
    }
    for attr in ("dtstart", "dtend", "description", "location"):
        if hasattr(ve, attr):
            v = getattr(ve, attr).value
            out[attr] = v.isoformat() if hasattr(v, "isoformat") else str(v)
    return out


def _vtodo_summary(todo) -> dict[str, Any]:
    vc = todo.vobject_instance
    vt = vc.vtodo
    out: dict[str, Any] = {
        "uid": str(vt.uid.value),
        "summary": str(getattr(vt, "summary", "").value) if hasattr(vt, "summary") else "",
        "url": str(todo.url),
    }
    for attr in ("due", "description", "status", "priority", "completed"):
        if hasattr(vt, attr):
            v = getattr(vt, attr).value
            out[attr] = v.isoformat() if hasattr(v, "isoformat") else str(v)
    return out


def _vcard_summary(card) -> dict[str, Any]:
    vc = card.vobject_instance
    out: dict[str, Any] = {
        "uid": str(vc.uid.value) if hasattr(vc, "uid") else "",
        "url": str(card.url),
        "fn": str(vc.fn.value) if hasattr(vc, "fn") else "",
    }
    # Collect emails (may be multiple).
    emails = []
    for e in vc.contents.get("email", []) or []:
        emails.append(str(e.value))
    if emails:
        out["email"] = emails
    # Collect phone numbers.
    tels = []
    for t in vc.contents.get("tel", []) or []:
        tels.append(str(t.value))
    if tels:
        out["tel"] = tels
    if hasattr(vc, "org"):
        out["org"] = ";".join(vc.org.value) if isinstance(vc.org.value, list) else str(vc.org.value)
    if hasattr(vc, "note"):
        out["note"] = str(vc.note.value)
    return out


# ── MCP server ──────────────────────────────────────────────────────────────

mcp = FastMCP("radicale")


# ── discovery tools ────────────────────────────────────────────────────────

@mcp.tool()
async def calendar_list() -> list[dict[str, Any]]:
    """List all calendars on the configured Radicale account."""
    cals = _principal().calendars()
    return [{"name": c.name, "url": str(c.url)} for c in cals]


@mcp.tool()
async def addressbook_list() -> list[dict[str, Any]]:
    """List all address books on the configured Radicale account."""
    abs_ = _principal().addressbooks()
    return [{"name": a.name, "url": str(a.url)} for a in abs_]


# ── events ─────────────────────────────────────────────────────────────────

_RRULE_KEYS_SCALAR = {"FREQ", "INTERVAL", "COUNT", "WKST", "UNTIL"}
_RRULE_KEYS_LIST = {
    "BYDAY", "BYMONTHDAY", "BYYEARDAY", "BYWEEKNO",
    "BYMONTH", "BYSETPOS", "BYHOUR", "BYMINUTE", "BYSECOND",
}


def _normalize_rrule(rrule: str | dict | None) -> str | None:
    """Accept RRULE in either RFC-5545 string form (`FREQ=WEEKLY;BYDAY=MO,WE`)
    or dict form (`{"FREQ":"WEEKLY","BYDAY":["MO","WE"]}`) and return the
    canonical RFC-5545 string for embedding into the VEVENT. Returns None
    when the input is None/empty.

    Validates FREQ is set + uppercases keys + comma-joins list values.
    Does NOT validate that key/value combinations form a valid RRULE —
    the upstream calendar will reject malformed input on save."""
    if rrule is None:
        return None
    if isinstance(rrule, str):
        s = rrule.strip()
        if not s:
            return None
        # Accept "RRULE:FREQ=..." prefix and strip it.
        if s.upper().startswith("RRULE:"):
            s = s[6:]
        if "FREQ=" not in s.upper():
            raise ValueError(
                f"RRULE string must contain FREQ=… (got {s!r})"
            )
        return s
    if isinstance(rrule, dict):
        if not rrule:
            return None
        parts: list[str] = []
        upper = {k.upper(): v for k, v in rrule.items()}
        if "FREQ" not in upper:
            raise ValueError(
                "RRULE dict must contain FREQ key (e.g. 'DAILY', 'WEEKLY', "
                "'MONTHLY', 'YEARLY')"
            )
        # FREQ first by convention
        parts.append(f"FREQ={str(upper['FREQ']).upper()}")
        for key, val in upper.items():
            if key == "FREQ":
                continue
            if key in _RRULE_KEYS_LIST and isinstance(val, (list, tuple)):
                parts.append(f"{key}={','.join(str(v).upper() for v in val)}")
            elif key == "UNTIL":
                # Allow either RFC-5545 form (20261231T235959Z) or ISO-8601 —
                # normalize ISO to the basic form caldav expects.
                v = str(val).replace("-", "").replace(":", "")
                if "T" not in v:
                    v = f"{v}T000000Z"
                elif not v.endswith("Z"):
                    v = f"{v}Z"
                parts.append(f"UNTIL={v}")
            else:
                parts.append(f"{key}={val}")
        return ";".join(parts)
    raise TypeError(
        f"rrule must be str, dict, or None (got {type(rrule).__name__})"
    )


@mcp.tool()
async def event_create(
    summary: str,
    start: str,
    end: str,
    calendar: str | None = None,
    description: str | None = None,
    location: str | None = None,
    tz: str | None = None,
    rrule: str | dict | None = None,
) -> dict[str, Any]:
    """Create a calendar event (VEVENT).

    `start` / `end` are ISO-8601 datetimes. If they don't include a
    timezone offset or 'Z' suffix, they're interpreted in the IANA zone
    `tz` (e.g. 'America/Chicago'); if `tz` is also omitted, the server's
    configured default zone is used (defaults to the saruman host zone).

    Examples:
      start='2026-05-12T15:00:00', tz='America/Chicago'  → 3pm Central
      start='2026-05-12T15:00:00-05:00'                  → 3pm UTC-5
      start='2026-05-12T20:00:00Z'                       → 8pm UTC

    `calendar` is the display name; if omitted, uses the first calendar.

    `rrule` makes the event recurring. Accepts either:
      • RFC-5545 string: 'FREQ=WEEKLY;BYDAY=MO,WE,FR;UNTIL=20261231T235959Z'
      • dict form:       {'FREQ': 'WEEKLY', 'BYDAY': ['MO','WE','FR'],
                          'UNTIL': '2026-12-31T23:59:59'}
    FREQ is required (DAILY/WEEKLY/MONTHLY/YEARLY). Common companions:
      INTERVAL=N         every Nth occurrence
      COUNT=N            stop after N occurrences (mutex with UNTIL)
      UNTIL=<iso|basic>  stop on/before this datetime
      BYDAY=MO,WE,FR     for WEEKLY: which weekdays
      BYMONTHDAY=15      for MONTHLY: which day-of-month
      BYMONTH=1,6,12     for YEARLY: which months
      WKST=SU            week start (rarely needed)

    Examples:
      • Weekly on Wed at 3pm:
          start='2026-05-13T15:00:00', tz='America/Chicago',
          rrule={'FREQ':'WEEKLY','BYDAY':['WE']}
      • Every weekday for 10 occurrences:
          rrule={'FREQ':'WEEKLY','BYDAY':['MO','TU','WE','TH','FR'],
                 'COUNT':10}
      • First of every month until end of year:
          rrule={'FREQ':'MONTHLY','BYMONTHDAY':1,
                 'UNTIL':'2026-12-31T23:59:59'}
      • Yearly on May 14:
          rrule='FREQ=YEARLY'   (DTSTART carries the date, FREQ alone is enough)

    The created event's UID is returned; use it with event_update /
    event_delete to manage the whole series. Per-occurrence overrides
    (RECURRENCE-ID) aren't currently supported here — modify or delete
    the master event, or fall through to the radicale web UI.
    """
    cal = _find_calendar(calendar)
    dts, dte = _parse_dt(start, tz), _parse_dt(end, tz)
    uid = str(uuid4())
    rrule_str = _normalize_rrule(rrule)
    event = cal.save_event(
        dtstart=dts,
        dtend=dte,
        summary=summary,
        description=description,
        location=location,
        uid=uid,
    )
    # caldav's save_event helper doesn't accept RRULE as a kwarg in the
    # version we use, so attach via vobject post-save (same pattern as
    # event_update's description/location handling). icalendar parses the
    # RRULE string into a dict-of-lists on the wire, so we set the raw
    # string value and let it round-trip.
    if rrule_str:
        vc = event.vobject_instance
        ve = vc.vevent
        if hasattr(ve, "rrule"):
            ve.rrule.value = rrule_str
        else:
            ve.add("rrule").value = rrule_str
        event.save()
    return {
        "uid": uid,
        "calendar": cal.name,
        "summary": summary,
        "start": dts.isoformat(),
        "end": dte.isoformat(),
        "rrule": rrule_str,
    }


@mcp.tool()
async def event_list(
    calendar: str | None = None,
    start: str | None = None,
    end: str | None = None,
    limit: int = 50,
    tz: str | None = None,
) -> list[dict[str, Any]]:
    """List events in a calendar within an optional [start, end] window.
    Window endpoints follow the same tz rules as event_create — naive
    strings get the configured default zone.
    """
    cal = _find_calendar(calendar)
    kwargs: dict[str, Any] = {}
    if start:
        kwargs["start"] = _parse_dt(start, tz)
    if end:
        kwargs["end"] = _parse_dt(end, tz)
    if kwargs:
        events = cal.search(event=True, **kwargs)
    else:
        events = cal.events()
    return [_vevent_summary(e) for e in events[:limit]]


@mcp.tool()
async def event_update(
    uid: str,
    calendar: str | None = None,
    summary: str | None = None,
    start: str | None = None,
    end: str | None = None,
    description: str | None = None,
    location: str | None = None,
    tz: str | None = None,
    rrule: str | dict | None = None,
    clear_rrule: bool = False,
) -> dict[str, Any]:
    """Update fields on an existing event by UID. `start`/`end` follow the
    same tz rules as event_create. Pass `rrule` to set or replace the
    recurrence (same accepted forms as event_create — string or dict);
    pass `clear_rrule=True` to remove an existing RRULE and make the
    event a one-shot. `rrule` and `clear_rrule` are mutually exclusive.
    """
    if rrule is not None and clear_rrule:
        raise ValueError("pass either rrule or clear_rrule, not both")
    cal = _find_calendar(calendar)
    event = cal.event_by_uid(uid)
    vc = event.vobject_instance
    ve = vc.vevent
    if summary is not None:
        ve.summary.value = summary
    if start is not None:
        ve.dtstart.value = _parse_dt(start, tz)
    if end is not None:
        ve.dtend.value = _parse_dt(end, tz)
    if description is not None:
        if hasattr(ve, "description"):
            ve.description.value = description
        else:
            ve.add("description").value = description
    if location is not None:
        if hasattr(ve, "location"):
            ve.location.value = location
        else:
            ve.add("location").value = location
    if clear_rrule and hasattr(ve, "rrule"):
        # vobject doesn't expose a delete; remove from the contents list.
        ve.contents.pop("rrule", None)
    elif rrule is not None:
        rrule_str = _normalize_rrule(rrule)
        if rrule_str is None:
            # An explicitly-None-after-normalize is treated as clear too.
            ve.contents.pop("rrule", None)
        elif hasattr(ve, "rrule"):
            ve.rrule.value = rrule_str
        else:
            ve.add("rrule").value = rrule_str
    event.save()
    return _vevent_summary(event)


@mcp.tool()
async def event_delete(uid: str, calendar: str | None = None) -> dict[str, Any]:
    """Delete an event by UID."""
    cal = _find_calendar(calendar)
    event = cal.event_by_uid(uid)
    event.delete()
    return {"deleted": True, "uid": uid}


# ── tasks (VTODO) ──────────────────────────────────────────────────────────

@mcp.tool()
async def task_create(
    summary: str,
    calendar: str | None = None,
    due: str | None = None,
    description: str | None = None,
    priority: int | None = None,
    tz: str | None = None,
) -> dict[str, Any]:
    """Create a task (VTODO) in the given calendar. `due` follows the same
    timezone rules as event_create.
    """
    cal = _find_calendar(calendar)
    uid = str(uuid4())
    kwargs: dict[str, Any] = {"summary": summary, "uid": uid}
    if due is not None:
        kwargs["due"] = _parse_dt(due, tz)
    if description is not None:
        kwargs["description"] = description
    if priority is not None:
        kwargs["priority"] = priority
    cal.save_todo(**kwargs)
    return {"uid": uid, "calendar": cal.name, "summary": summary}


@mcp.tool()
async def task_list(
    calendar: str | None = None,
    include_completed: bool = False,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """List tasks (VTODO) in a calendar. By default excludes completed."""
    cal = _find_calendar(calendar)
    todos = cal.todos(include_completed=include_completed)
    return [_vtodo_summary(t) for t in todos[:limit]]


@mcp.tool()
async def task_complete(uid: str, calendar: str | None = None) -> dict[str, Any]:
    """Mark a task as completed."""
    cal = _find_calendar(calendar)
    todo = cal.todo_by_uid(uid)
    todo.complete()
    return _vtodo_summary(todo)


@mcp.tool()
async def task_delete(uid: str, calendar: str | None = None) -> dict[str, Any]:
    """Delete a task by UID."""
    cal = _find_calendar(calendar)
    todo = cal.todo_by_uid(uid)
    todo.delete()
    return {"deleted": True, "uid": uid}


# ── contacts (VCARD) ───────────────────────────────────────────────────────

@mcp.tool()
async def contact_create(
    fn: str,
    addressbook: str | None = None,
    email: str | None = None,
    tel: str | None = None,
    org: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    """Create a contact (VCARD) in the given address book.

    `fn` is the formatted name ("First Last"). `email` and `tel` are single
    values for now — for multi-value, use contact_update after creation.
    """
    ab = _find_addressbook(addressbook)
    uid = str(uuid4())
    card = vobject.vCard()
    card.add("fn").value = fn
    card.add("n").value = vobject.vcard.Name(family=fn.split()[-1] if fn else "", given=" ".join(fn.split()[:-1]) if " " in fn else fn)
    card.add("uid").value = uid
    if email is not None:
        e = card.add("email"); e.value = email; e.type_param = "INTERNET"
    if tel is not None:
        t = card.add("tel"); t.value = tel; t.type_param = "CELL"
    if org is not None:
        card.add("org").value = [org]
    if note is not None:
        card.add("note").value = note
    ab.save_vcard(card.serialize())
    return {"uid": uid, "addressbook": ab.name, "fn": fn}


@mcp.tool()
async def contact_list(
    addressbook: str | None = None,
    limit: int = 200,
) -> list[dict[str, Any]]:
    """List contacts in the given address book."""
    ab = _find_addressbook(addressbook)
    cards = ab.objects()
    return [_vcard_summary(c) for c in cards[:limit]]


@mcp.tool()
async def contact_search(
    query: str,
    addressbook: str | None = None,
    limit: int = 50,
) -> list[dict[str, Any]]:
    """Substring search across contact FN / email / tel / org / note.
    Case-insensitive.
    """
    ab = _find_addressbook(addressbook)
    q = query.lower()
    out: list[dict[str, Any]] = []
    for c in ab.objects():
        summary = _vcard_summary(c)
        blob = " ".join(
            str(v) for v in [
                summary.get("fn", ""),
                *summary.get("email", []),
                *summary.get("tel", []),
                summary.get("org", ""),
                summary.get("note", ""),
            ]
        ).lower()
        if q in blob:
            out.append(summary)
            if len(out) >= limit:
                break
    return out


@mcp.tool()
async def contact_update(
    uid: str,
    addressbook: str | None = None,
    fn: str | None = None,
    email: str | None = None,
    tel: str | None = None,
    org: str | None = None,
    note: str | None = None,
) -> dict[str, Any]:
    """Update fields on a contact. Single-value semantics — replaces the
    existing first email / tel / etc. if provided.
    """
    ab = _find_addressbook(addressbook)
    # Radicale URLs end with .vcf; use the addressbook's search via UID.
    found = None
    for c in ab.objects():
        v = c.vobject_instance
        if hasattr(v, "uid") and str(v.uid.value) == uid:
            found = c
            break
    if found is None:
        return {"error": f"contact uid {uid} not found"}
    v = found.vobject_instance
    if fn is not None:
        if hasattr(v, "fn"):
            v.fn.value = fn
        else:
            v.add("fn").value = fn
    if email is not None:
        if v.contents.get("email"):
            v.email.value = email
        else:
            e = v.add("email"); e.value = email; e.type_param = "INTERNET"
    if tel is not None:
        if v.contents.get("tel"):
            v.tel.value = tel
        else:
            t = v.add("tel"); t.value = tel; t.type_param = "CELL"
    if org is not None:
        if hasattr(v, "org"):
            v.org.value = [org]
        else:
            v.add("org").value = [org]
    if note is not None:
        if hasattr(v, "note"):
            v.note.value = note
        else:
            v.add("note").value = note
    found.save()
    return _vcard_summary(found)


@mcp.tool()
async def contact_delete(uid: str, addressbook: str | None = None) -> dict[str, Any]:
    """Delete a contact by UID."""
    ab = _find_addressbook(addressbook)
    for c in ab.objects():
        v = c.vobject_instance
        if hasattr(v, "uid") and str(v.uid.value) == uid:
            c.delete()
            return {"deleted": True, "uid": uid}
    return {"error": f"contact uid {uid} not found"}


# ── /version (bearer-required) ──────────────────────────────────────────────

async def version_route(_request: Request) -> JSONResponse:
    return JSONResponse({"name": "radicale-mcp", "version": __version__})


# ── /health (no auth) ───────────────────────────────────────────────────────

async def health(_request: Request) -> JSONResponse:
    assert CFG is not None
    ok = False
    err: dict[str, str] = {}
    try:
        cals = _principal().calendars()
        abs_ = _principal().addressbooks()
        ok = True
        return JSONResponse(
            {
                "status": "ok",
                "radicale_url": CFG.radicale_url,
                "calendars": [c.name for c in cals],
                "addressbooks": [a.name for a in abs_],
            }
        )
    except Exception as e:  # noqa: BLE001
        err["radicale"] = repr(e)
    return JSONResponse(
        {"status": "degraded", "radicale_url": CFG.radicale_url, **({"errors": err} if err else {})}
    )


# ── lifespan + main ────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(_app: Starlette):
    async with mcp.session_manager.run():
        log.info("radicale-mcp ready (url=%s)", CFG.radicale_url if CFG else "?")
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
        print(f"radicale-mcp {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("RADICALE_MCP_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting radicale-mcp version %s on %s:%d (radicale=%s user=%s) with %d client tokens",
        __version__, bind_ip, CFG.port, CFG.radicale_url, CFG.radicale_user, len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
