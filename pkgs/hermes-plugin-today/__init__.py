"""Morning briefing plugin for hermes-agent.

Slash command: `/today` →
  1. Creates today's Obsidian daily note from the Templater template
     (only if it doesn't already exist — idempotent).
  2. Pulls today's events from radicale (default calendar) + gcal
     (Google read-only).
  3. Pulls open radicale tasks.
  4. Walks 05 - personal notes/YYYY/MM/ for open `- [ ]` items
     tagged `#tasks` — mirrors the in-Obsidian Dataview query the
     daily-note template runs. Most-recent daily notes first, capped
     at VAULT_TODO_CAP.
  5. One Gemini Flash Lite call (BYOK) for a "shape of the day" one-liner.
  6. Returns the brief to Signal.

Env requirements (set by hermes-agent.env template):
  - OPENROUTER_API_KEY
  - HERMES_RADICALE_MCP_TOKEN
  - HERMES_GCAL_MCP_TOKEN

Filesystem assumptions:
  - Vault root: /home/alex/obsidian/Barrow-Downs
  - Template:   98 - templates/daily note - template.md
  - Daily notes land at 05 - personal notes/YYYY/MM/<MMM-Dth-YYYY>.md
  - Process runs as alex (uid 1000) so /home/alex/ is read+write.

`/today raw` skips the LLM synthesis line (pure data dump).
`/today no-note` skips the daily-note creation step (briefing only).
"""

from __future__ import annotations

import json
import logging
import os
import re
from datetime import date, datetime, time, timedelta, timezone
from pathlib import Path

import httpx

log = logging.getLogger("hermes.plugins.today")

VAULT_ROOT = Path(os.environ.get(
    "VAULT_ROOT", "/home/alex/obsidian/Barrow-Downs"
))
DAILY_NOTE_DIR = "05 - personal notes"
TEMPLATE_PATH = VAULT_ROOT / "98 - templates" / "daily note - template.md"
DAILY_NOTES_ROOT = VAULT_ROOT / DAILY_NOTE_DIR

OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
SYNTH_MODEL = "google/gemini-2.5-flash-lite"

# The MCPs bind to saruman's tailnet IP only — the `saruman` hostname
# resolves to its LAN IP, which the MCP listener doesn't accept. The
# nix module injects the real URLs as env vars (same values hermes
# uses in mcpServers.*.url) so we don't duplicate the resolution.
#
# Resolve at call time, not module-import time. hermes-agent's
# load_hermes_dotenv() runs AFTER plugin __init__.py is imported, so
# module-level os.environ reads see only the systemd-unit Environment=
# subset (which doesn't include these vars). Reading inside the
# functions defers until after dotenv has populated os.environ.

def _radicale_url() -> str:
    return os.environ.get(
        "HERMES_PLUGIN_RADICALE_URL", "http://127.0.0.1:4283/mcp"
    )

def _gcal_url() -> str:
    return os.environ.get(
        "HERMES_PLUGIN_GCAL_URL", "http://127.0.0.1:4286/mcp"
    )
VAULT_TODO_CAP = 20
TASK_TAG = "#tasks"
# How far ahead radicale tasks need to be due to still show in the
# brief. Anything further out is "future me's problem" — keep the
# briefing focused on what's actually actionable this fortnight.
# Undated tasks are kept regardless (they're ad-hoc TODOs without a
# scheduled deadline, and dropping them would hide real work).
TASK_WINDOW_DAYS = 14

# Matches "- [ ] text..." at any indent. We *do* keep the `\s*` indent-
# prefix because nested children of an unchecked top-level often carry
# the actual operational text, and the Dataview query that drives alex's
# Obsidian view doesn't discriminate by indentation either.
CHECKBOX_RE = re.compile(r"^\s*-\s*\[\s\]\s*(.+?)\s*$")
# Match the canonical YYYY-MM-DD date a daily-note filename encodes.
# Filename shape is "MMM-Dth-YYYY.md" — same format _title_for produces.
DAILY_NOTE_FN_RE = re.compile(
    r"^([A-Z][a-z]{2})-(\d{1,2})(?:st|nd|rd|th)-(\d{4})\.md$"
)

SYNTH_SYSTEM = """You are writing a single-sentence "shape of the day"
caption for a morning briefing. You'll be given a structured day-state
(calendar events, tasks, vault TODOs). Output ONE sentence — at most
~20 words — calling out the most operationally important thing in the
day. Tone: dry, terse, no fluff, no emoji, no preamble. If the day is
quiet, say so. Just the sentence. No markdown."""


# ─── Date helpers ───────────────────────────────────────────────────────────

def _ordinal_suffix(n: int) -> str:
    """English ordinal suffix: 1st, 2nd, 3rd, 4th, … 11th, 21st, 22nd, 23rd."""
    if 10 <= (n % 100) <= 20:
        return "th"
    return {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")


def _title_for(d: date) -> str:
    """Format like 'May-7th-2026' — matches the Templater output."""
    return f"{d.strftime('%b')}-{d.day}{_ordinal_suffix(d.day)}-{d.year}"


# ─── Daily note creation ────────────────────────────────────────────────────

def _ensure_daily_note(today: date) -> tuple[Path, bool]:
    """Create today's daily note from the Templater template if it
    doesn't already exist. Returns (path, created_bool). Idempotent —
    safe to call multiple times per day.
    """
    title = _title_for(today)
    target_dir = (
        VAULT_ROOT / DAILY_NOTE_DIR / f"{today.year}" / f"{today.month:02d}"
    )
    target = target_dir / f"{title}.md"
    if target.exists():
        return target, False

    if not TEMPLATE_PATH.is_file():
        raise RuntimeError(f"template missing at {TEMPLATE_PATH}")

    target_dir.mkdir(parents=True, exist_ok=True)
    template = TEMPLATE_PATH.read_text(encoding="utf-8")

    # Strip the Templater command lines (`<%* ... -%>`). These run in
    # Obsidian to set file location + trigger dataview refresh, neither
    # of which applies to our pre-placed file.
    body = re.sub(r"<%\*.*?%>\n?", "", template, flags=re.DOTALL)

    # Substitute remaining Templater expressions. The template uses
    # literal date-format strings we can resolve deterministically.
    yesterday = _title_for(today - timedelta(days=1))
    tomorrow = _title_for(today + timedelta(days=1))
    body = body.replace("<% tp.file.title %>", title)
    body = body.replace(
        '<% tp.date.now("MMM-Do-YYYY", -1, tp.file.title, "MMM-Do-YYYY") %>',
        yesterday,
    )
    body = body.replace(
        '<% tp.date.now("MMM-Do-YYYY", 1, tp.file.title, "MMM-Do-YYYY") %>',
        tomorrow,
    )

    # Fill frontmatter timestamps. Template ships them empty
    # ("date_created:\ndate_modified:") because Templater would write
    # them in Obsidian.
    now_iso = datetime.now().strftime("%Y-%m-%dT%H:%M:%S")
    body = body.replace(
        "date_created:\ndate_modified:",
        f"date_created: {now_iso}\ndate_modified: {now_iso}",
    )

    target.write_text(body, encoding="utf-8")
    return target, True


# ─── Daily-note TODO walker ─────────────────────────────────────────────────

_MONTH_TO_NUM = {
    "Jan": 1, "Feb": 2, "Mar": 3, "Apr": 4, "May": 5, "Jun": 6,
    "Jul": 7, "Aug": 8, "Sep": 9, "Oct": 10, "Nov": 11, "Dec": 12,
}


def _daily_note_date(filename: str) -> date | None:
    """Parse a daily-note filename ("May-7th-2026.md") to a date.
    Returns None if the filename doesn't match the canonical shape — we
    skip non-daily files in the daily-notes folder rather than guess.
    """
    m = DAILY_NOTE_FN_RE.match(filename)
    if not m:
        return None
    mon, day, year = m.group(1), int(m.group(2)), int(m.group(3))
    if mon not in _MONTH_TO_NUM:
        return None
    try:
        return date(year, _MONTH_TO_NUM[mon], day)
    except ValueError:
        return None


def _extract_tagged_open_tasks(path: Path) -> list[str]:
    """Return open `- [ ]` lines from a file whose body contains the
    canonical `#tasks` tag. Matches alex's existing Dataview convention:

        TASK FROM "05 - personal notes" WHERE !completed
        AND contains(tags, "#tasks") AND file.frontmatter.type = "daily"

    We grep inline only — file-level `tags:` frontmatter is not applied
    to individual tasks because alex's convention puts `#tasks` directly
    on the task line.
    """
    out: list[str] = []
    try:
        for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
            m = CHECKBOX_RE.match(raw)
            if not m:
                continue
            text = m.group(1).strip()
            if not text or TASK_TAG not in text:
                continue
            # Strip the `#tasks` token from the displayed text — it's
            # a routing marker, not part of the task description. Use a
            # word-boundary regex so `#tasksboard` (if it ever exists)
            # wouldn't be stripped.
            cleaned = re.sub(r"\s*#tasks\b\s*", " ", text).strip()
            out.append(cleaned or text)
    except OSError:
        pass
    return out


def _walk_daily_note_tasks() -> list[tuple[date, str]]:
    """Walk every daily note under 05 - personal notes/YYYY/MM/ and
    collect open `- [ ]` lines tagged `#tasks`. Returned list is
    sorted by note-date descending (most recent first), capped to
    VAULT_TODO_CAP.
    """
    if not DAILY_NOTES_ROOT.is_dir():
        return []

    items: list[tuple[date, str]] = []
    for p in DAILY_NOTES_ROOT.rglob("*.md"):
        d = _daily_note_date(p.name)
        if d is None:
            continue
        for task in _extract_tagged_open_tasks(p):
            items.append((d, task))

    items.sort(key=lambda x: x[0], reverse=True)
    return items[:VAULT_TODO_CAP]


# ─── MCP calls (radicale + gcal) ────────────────────────────────────────────

async def _mcp_call(
    client: httpx.AsyncClient, url: str, token: str, tool: str, args: dict
) -> dict | list | None:
    """Talk to a streamable-HTTP MCP via the bare protocol. We only
    need a single tool call, so a full mcp.ClientSession with its
    initialize handshake is overkill — bypass it with one initialize +
    one tools/call, parsing the resulting SSE-formatted response.

    Returns the parsed JSON payload of the tool's first content item,
    or None on any error (logged).
    """
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
        "Accept": "application/json, text/event-stream",
    }
    try:
        # 1) initialize
        init_resp = await client.post(
            url,
            headers=headers,
            json={
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": "2025-06-18",
                    "capabilities": {},
                    "clientInfo": {"name": "hermes-plugin-today", "version": "0.1"},
                },
            },
            timeout=15.0,
        )
        init_resp.raise_for_status()
        # streamable_http returns a session id in headers we must echo back.
        session_id = init_resp.headers.get("mcp-session-id")
        if session_id:
            headers["mcp-session-id"] = session_id
        # 2) notifications/initialized — required by the spec, ack only.
        await client.post(
            url,
            headers=headers,
            json={"jsonrpc": "2.0", "method": "notifications/initialized"},
            timeout=10.0,
        )
        # 3) tools/call
        r = await client.post(
            url,
            headers=headers,
            json={
                "jsonrpc": "2.0",
                "id": 2,
                "method": "tools/call",
                "params": {"name": tool, "arguments": args},
            },
            timeout=30.0,
        )
        r.raise_for_status()
    except Exception as e:  # noqa: BLE001
        log.warning("MCP call %s on %s failed: %s", tool, url, e)
        return None

    # Body may be JSON or SSE-framed JSON ("data: {...}\n\n").
    body = r.text.strip()
    if body.startswith("event:") or "\ndata:" in body or body.startswith("data:"):
        # Pull the first `data:` line.
        for line in body.splitlines():
            if line.startswith("data:"):
                body = line[5:].strip()
                break
    try:
        payload = json.loads(body)
    except json.JSONDecodeError:
        log.warning("MCP %s returned unparseable body: %r", tool, body[:200])
        return None

    if "error" in payload:
        log.warning("MCP %s error: %s", tool, payload["error"])
        return None
    result = payload.get("result", {})

    # PREFER structuredContent.result when present — that's the
    # canonical machine-readable shape for a tool that returns a list
    # (e.g. calendar_list, event_list). The legacy `content` array
    # serializes each list item as a SEPARATE entry, so parsing only
    # `content[0]` truncates list-returning tools to their first item.
    structured = result.get("structuredContent")
    if isinstance(structured, dict) and "result" in structured:
        return structured["result"]

    contents = result.get("content", [])
    if not contents:
        return None
    # Multiple content entries → each is a list item. Parse them all,
    # falling back to single-item shape if there's only one and it's a
    # JSON object/array.
    if len(contents) > 1:
        parsed_list: list = []
        for c in contents:
            t = c.get("text", "")
            try:
                parsed_list.append(json.loads(t))
            except json.JSONDecodeError:
                parsed_list.append(t)
        return parsed_list

    text = contents[0].get("text", "")
    try:
        return json.loads(text)
    except json.JSONDecodeError:
        return text  # tool returned plain text; caller decides


def _event_start_date_str(e: dict) -> str | None:
    """Pull the calendar-day a returned event STARTS on, in
    YYYY-MM-DD shape. Handles both:
      • all-day events: start = {"date": "2026-05-14"}
      • timed events:   start = {"dateTime": "2026-05-14T14:00:00-05:00"}
      • radicale shape: start = "2026-05-14T14:00:00-05:00" (bare string)
    Returns None if we can't parse.
    """
    s = e.get("start")
    if isinstance(s, str):
        return s[:10] if len(s) >= 10 else None
    if isinstance(s, dict):
        if isinstance(s.get("date"), str):
            return s["date"][:10]
        if isinstance(s.get("dateTime"), str):
            return s["dateTime"][:10]
    return None


async def _fetch_calendar_events(client: httpx.AsyncClient, today: date) -> dict:
    """Return {radicale: [...], gcal: [...]} of today's events.

    Each list element is a normalized dict: {start, end, title,
    location?, all_day, source}.

    Window math runs in the system's local timezone (CDT for saruman),
    not UTC. Using UTC midnight as the day boundary leaks the evening
    portion of yesterday into "today" for any operator not in UTC.

    Results from gcal in particular are then filtered client-side to
    keep ONLY events whose start date matches today_local — Google's
    timeMin/timeMax use "events overlapping the window" semantics, so
    a yesterday-all-day event whose exclusive end is today-00:00 leaks
    through unless we re-check.
    """
    local_tz = datetime.now().astimezone().tzinfo
    today_str = today.isoformat()
    start_iso = datetime.combine(today, time.min, tzinfo=local_tz).isoformat()
    end_iso = datetime.combine(
        today + timedelta(days=1), time.min, tzinfo=local_tz
    ).isoformat()

    rad_tok = os.environ.get("HERMES_RADICALE_MCP_TOKEN", "")
    gcal_tok = os.environ.get("HERMES_GCAL_MCP_TOKEN", "")

    radicale_events: list[dict] = []
    if rad_tok:
        # radicale-mcp's event_list defaults to the user's FIRST calendar
        # when calendar=None — which is "ToDo" in alex's account (tasks
        # only, no events). The real events live on "General". Per SOUL.md
        # default is to query every radicale calendar and merge. Enumerate
        # via calendar_list, then event_list per calendar.
        cals_resp = await _mcp_call(
            client, _radicale_url(), rad_tok, "calendar_list", {},
        )
        cal_names: list[str] = []
        if isinstance(cals_resp, list):
            cal_names = [c.get("name") for c in cals_resp if c.get("name")]
        elif isinstance(cals_resp, dict) and "result" in cals_resp:
            cal_names = [
                c.get("name") for c in cals_resp["result"] if c.get("name")
            ]

        for name in cal_names:
            rad = await _mcp_call(
                client, _radicale_url(), rad_tok, "event_list",
                {"calendar": name, "start": start_iso, "end": end_iso},
            )
            events = rad if isinstance(rad, list) else (
                rad.get("events") or rad.get("result") or []
                if isinstance(rad, dict) else []
            )
            for e in events:
                # Same belt-and-suspenders check as for gcal — caldav's
                # range query is generally tighter, but the cost of an
                # extra check here is zero and prevents future-me from
                # being confused if a radicale evening event leaks.
                ev_start = _event_start_date_str(e)
                if ev_start and ev_start != today_str:
                    continue
                e["_calendar"] = name
                radicale_events.append(e)

    gcal_events: list[dict] = []
    if gcal_tok:
        # gcal_event_list defaults to calendar="primary" — that misses
        # shared calendars (the important ones for alex). Enumerate via
        # gcal_calendar_list and query each. Cap at MAX_GCAL_CALENDARS
        # to bound latency in case the account has 20+ subscribed
        # holiday/sports calendars.
        cals_resp = await _mcp_call(
            client, _gcal_url(), gcal_tok, "gcal_calendar_list", {},
        )
        cal_entries: list[dict] = []
        if isinstance(cals_resp, list):
            cal_entries = cals_resp
        elif isinstance(cals_resp, dict) and "result" in cals_resp:
            cal_entries = cals_resp["result"]

        # Prefer primary + owner/writer calendars (the ones alex
        # actively maintains) before reader-only subscriptions. Keep
        # readers too — a shared work calendar shows up as access_role
        # "reader" if alex was invited read-only.
        def _priority(c: dict) -> int:
            if c.get("primary"):
                return 0
            role = (c.get("access_role") or "").lower()
            return {"owner": 1, "writer": 2, "reader": 3}.get(role, 4)

        cal_entries.sort(key=_priority)
        MAX_GCAL_CALENDARS = 8

        for cal in cal_entries[:MAX_GCAL_CALENDARS]:
            cid = cal.get("id")
            if not cid:
                continue
            gc = await _mcp_call(
                client, _gcal_url(), gcal_tok, "gcal_event_list",
                {
                    "calendar": cid,
                    "start": start_iso,
                    "end": end_iso,
                    "limit": 30,
                },
            )
            events = gc if isinstance(gc, list) else []
            for e in events:
                if isinstance(e, dict) and e.get("error"):
                    # gcal_event_list returns [{"error": "..."}] on
                    # failure — skip rather than poison the list.
                    continue
                # Discard events whose START date isn't today —
                # Google's overlap semantics leak yesterday all-day
                # events whose exclusive end is today-00:00.
                ev_start = _event_start_date_str(e)
                if ev_start and ev_start != today_str:
                    continue
                e["_calendar"] = cal.get("summary") or cid
                gcal_events.append(e)

    return {"radicale": radicale_events, "gcal": gcal_events}


async def _fetch_radicale_tasks(client: httpx.AsyncClient) -> list[dict]:
    tok = os.environ.get("HERMES_RADICALE_MCP_TOKEN", "")
    if not tok:
        return []
    r = await _mcp_call(client, _radicale_url(), tok, "task_list", {})
    if isinstance(r, list):
        return r
    if isinstance(r, dict) and "tasks" in r:
        return r["tasks"]
    return []


# ─── Task filtering ─────────────────────────────────────────────────────────

def _task_due_date(t: dict) -> date | None:
    """Extract a date from a radicale task's `due` field. Handles
    YYYY-MM-DD, ISO datetimes with/without tz, and missing/None.
    Returns None when no parseable date is present.
    """
    raw = t.get("due") or t.get("due_date")
    if not raw or not isinstance(raw, str):
        return None
    # Take the first 10 chars — that's YYYY-MM-DD whether the field
    # is a bare date or a full ISO timestamp.
    head = raw[:10]
    try:
        return date.fromisoformat(head)
    except ValueError:
        return None


def _task_in_window(t: dict, today: date) -> bool:
    """Keep a task if it's open AND either (a) due within
    TASK_WINDOW_DAYS of today, including overdue, or (b) has no due
    date at all (ad-hoc todo without a deadline).
    """
    if t.get("completed", False):
        return False
    due = _task_due_date(t)
    if due is None:
        return True  # ad-hoc, no deadline → keep
    return due <= today + timedelta(days=TASK_WINDOW_DAYS)


# ─── Formatting ─────────────────────────────────────────────────────────────

def _fmt_event_time(start_iso: str | None, all_day: bool) -> str:
    if all_day or not start_iso:
        return "all-day"
    try:
        # Strip Z if present; fromisoformat in py3.11+ handles ±00:00 only.
        s = start_iso.replace("Z", "+00:00")
        dt = datetime.fromisoformat(s).astimezone()
        return dt.strftime("%H:%M")
    except Exception:
        return start_iso[:16]


def _fmt_event_line(e: dict, source: str) -> str:
    start = e.get("start") if isinstance(e.get("start"), str) else (e.get("start") or {}).get("dateTime") or (e.get("start") or {}).get("date")
    all_day = e.get("all_day") or (isinstance(e.get("start"), dict) and "date" in e.get("start"))
    when = _fmt_event_time(start, bool(all_day))
    title = e.get("summary") or e.get("title") or "(untitled)"
    # Per-event source tag: prefer the calendar name (set as _calendar
    # in _fetch_calendar_events) so alex can see which calendar an
    # event came from — important when shared calendars overlap.
    cal_name = e.get("_calendar") or ("primary" if source == "gcal" else "General")
    src_short = "gcal" if source == "gcal" else "rad"
    return f"  {when}  {title}  _{src_short}:{cal_name}_"


def _build_brief(
    today: date,
    note_path: Path,
    note_created: bool,
    calendar: dict,
    tasks: list[dict],
    daily_tasks: list[tuple[date, str]],
    shape_line: str | None,
) -> str:
    lines: list[str] = []
    lines.append(f"☀️ *Today* — {today.strftime('%a %b %-d')}")
    if shape_line:
        lines.append(f"_{shape_line.strip()}_")
    lines.append("")

    note_marker = "🆕 created" if note_created else "✓ existed"
    lines.append(f"📓 daily note: {note_path.name}  ({note_marker})")
    lines.append("")

    rad = calendar.get("radicale", [])
    gc = calendar.get("gcal", [])
    all_events = [(e, "radicale") for e in rad] + [(e, "gcal") for e in gc]
    if all_events:
        lines.append(f"📅 *Calendar* ({len(all_events)})")
        for e, src in sorted(
            all_events,
            key=lambda x: (
                x[0].get("start") if isinstance(x[0].get("start"), str)
                else (x[0].get("start") or {}).get("dateTime", "")
                or (x[0].get("start") or {}).get("date", "")
            ),
        ):
            lines.append(_fmt_event_line(e, src))
        lines.append("")

    open_tasks = [t for t in tasks if _task_in_window(t, today)]
    # Sort so overdue/imminent come first; undated drop to the bottom.
    open_tasks.sort(key=lambda t: (_task_due_date(t) or date.max))
    if open_tasks:
        far_count = sum(
            1 for t in tasks
            if not t.get("completed", False) and not _task_in_window(t, today)
        )
        header_suffix = (
            f" — {far_count} hidden (due >{TASK_WINDOW_DAYS}d out)"
            if far_count else ""
        )
        lines.append(f"✅ *Tasks* ({len(open_tasks)} open{header_suffix})")
        for t in open_tasks[:10]:
            summary = t.get("summary") or t.get("title") or "(untitled)"
            due = _task_due_date(t)
            if due is None:
                extra = ""
            elif due < today:
                extra = f"  _overdue {(today - due).days}d_"
            else:
                extra = f"  _due {due.isoformat()}_"
            lines.append(f"  • {summary}{extra}")
        lines.append("")

    if daily_tasks:
        lines.append(f"📝 *Open #tasks across daily notes* ({len(daily_tasks)})")
        for d, t in daily_tasks:
            # Same compact date shape as the daily-note filenames so
            # alex can jump to the source note quickly in Obsidian.
            tag = _title_for(d)
            lines.append(f"  • [{tag}] {t}")
        lines.append("")

    if not all_events and not open_tasks and not daily_tasks:
        lines.append("_(quiet day — no events, tasks, or open #tasks)_")

    return "\n".join(lines).rstrip()


# ─── LLM synthesis (shape-of-day one-liner) ─────────────────────────────────

async def _shape_of_day(client: httpx.AsyncClient, data: dict) -> str | None:
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        return None
    summary = json.dumps(data, default=str, ensure_ascii=False)
    try:
        r = await client.post(
            OPENROUTER_URL,
            headers={
                "Authorization": f"Bearer {key}",
                "Content-Type": "application/json",
            },
            json={
                "model": SYNTH_MODEL,
                "messages": [
                    {"role": "system", "content": SYNTH_SYSTEM},
                    {"role": "user", "content": summary},
                ],
                "temperature": 0.2,
            },
            timeout=30.0,
        )
        r.raise_for_status()
        return r.json()["choices"][0]["message"]["content"].strip()
    except Exception as e:  # noqa: BLE001
        log.warning("shape-of-day synth failed: %s", e)
        return None


# ─── Handler ────────────────────────────────────────────────────────────────

async def _run_today(raw: bool, skip_note: bool) -> str:
    today = date.today()

    if skip_note:
        note_path = (
            VAULT_ROOT / DAILY_NOTE_DIR / f"{today.year}" / f"{today.month:02d}"
            / f"{_title_for(today)}.md"
        )
        note_created = False
    else:
        try:
            note_path, note_created = _ensure_daily_note(today)
            if note_created:
                log.info("today: created daily note %s", note_path)
        except Exception as e:  # noqa: BLE001
            log.exception("today: daily note creation failed")
            return f"today error (daily note): {type(e).__name__}: {e}"

    async with httpx.AsyncClient() as client:
        calendar = await _fetch_calendar_events(client, today)
        tasks = await _fetch_radicale_tasks(client)
        daily_tasks = _walk_daily_note_tasks()

        shape: str | None = None
        if not raw:
            shape = await _shape_of_day(
                client,
                {
                    "calendar_count": (
                        len(calendar.get("radicale", []))
                        + len(calendar.get("gcal", []))
                    ),
                    "task_count": sum(
                        1 for t in tasks if _task_in_window(t, today)
                    ),
                    "daily_note_task_count": len(daily_tasks),
                    "sample_events": [
                        e.get("summary") or e.get("title")
                        for e in (calendar.get("radicale", []) + calendar.get("gcal", []))[:5]
                    ],
                    "sample_tasks": [
                        t.get("summary") or t.get("title")
                        for t in tasks[:5]
                    ],
                    "sample_daily_tasks": [t for _, t in daily_tasks[:5]],
                },
            )

    return _build_brief(
        today, note_path, note_created, calendar, tasks, daily_tasks, shape
    )


async def _handle_slash(raw_args: str):
    args = raw_args.strip().lower().split()
    if any(a in ("help", "-h", "--help") for a in args):
        return (
            "/today — morning briefing (calendar + tasks + vault TODOs).\n"
            "  raw      — skip the LLM shape-of-day one-liner.\n"
            "  no-note  — skip the daily-note creation step.\n"
            "Default: creates today's note (if missing) and synthesizes the line."
        )
    try:
        return await _run_today(
            raw="raw" in args,
            skip_note="no-note" in args,
        )
    except Exception as e:  # noqa: BLE001
        log.exception("today: unexpected failure")
        return f"today error: {type(e).__name__}: {e}"


def register(ctx) -> None:
    ctx.register_command(
        "today",
        handler=_handle_slash,
        description="Morning briefing — calendar, tasks, vault TODOs, daily note.",
        args_hint="[raw|no-note]",
    )
