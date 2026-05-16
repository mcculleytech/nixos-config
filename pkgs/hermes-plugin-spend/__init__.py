"""Spend tracker plugin for hermes-agent.

Slash command: `/spend [today|week|month|mtd]`

Primary source: OpenRouter's `/activity` endpoint queried with NO date
parameter — returns ~30 days of per-(date,model,endpoint) rows including
today's in-progress UTC day. (Only the `?date=YYYY-MM-DD` form requires a
completed UTC day and 400s on today; `?` and `?start=&end=` both happily
serve today's partial data. Earlier versions of this plugin built around
the wrong assumption.)

Secondary source: hermes' own `state.db`, used ONLY for sessions whose
`billing_provider` is `anthropic` (direct Anthropic API key, doesn't
transit OR) or `custom` (local Ollama / LM Studio — $0 regardless of
estimate). These never appear in OR /activity.

Sections of the brief:
  • OR balance — `/credits.total_remaining` for runway
  • Window total — sum of paid costs across all sources
  • By model — top spenders, sorted desc
  • By bill source — bucketed: `openrouter credit`, `google (BYOK via OR)`,
    `anthropic (via OR credit)`, `anthropic (direct)`, `local (free)`
  • Google Pro budget — MTD BYOK spend on google/* models against the
    $10/mo AI Studio Pro credit, with progress bar
  • Daily — per-day totals for short windows

For BYOK Google traffic, OR's `byok_usage_inference` is computed against
Google's actual per-token prices, so the figure aligns with what AI
Studio bills you. `usage` is OR-credit-billed spend; `byok_usage_inference`
is upstream-account spend. The two pools are independent and additive.
"""

from __future__ import annotations

import logging
import os
import sqlite3
from collections import defaultdict
from datetime import date, datetime, timedelta, timezone
from pathlib import Path

import httpx

log = logging.getLogger("hermes.plugins.spend")

OPENROUTER_API_URL = "https://openrouter.ai/api/v1"
HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/var/lib/hermes/.hermes"))
STATE_DB = HERMES_HOME / "state.db"

GOOGLE_PRO_MONTHLY_USD = 10.00


# ─── OpenRouter ────────────────────────────────────────────────────────────

async def _fetch_credits(client: httpx.AsyncClient) -> dict:
    """OR /credits — lifetime credits + total usage. Used for the runway
    balance line. Best-effort: returns {} on failure."""
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        return {}
    try:
        r = await client.get(
            f"{OPENROUTER_API_URL}/credits",
            headers={"Authorization": f"Bearer {key}"},
            timeout=10.0,
        )
        r.raise_for_status()
        return (r.json() or {}).get("data", {}) or {}
    except Exception as e:  # noqa: BLE001
        log.warning("spend: /credits fetch failed: %s", e)
        return {}


async def _fetch_activity(client: httpx.AsyncClient) -> list[dict]:
    """OR /activity, no date param. Returns ~30 days of per-row data
    including today's in-progress UTC day. Requires the provisioning
    (management) key — the runtime inference key gets 403 here."""
    key = os.environ.get("OPENROUTER_PROVISIONING_KEY", "")
    if not key or key.startswith("PLACEHOLDER"):
        log.warning("spend: OPENROUTER_PROVISIONING_KEY missing/placeholder")
        return []
    try:
        r = await client.get(
            f"{OPENROUTER_API_URL}/activity",
            headers={"Authorization": f"Bearer {key}"},
            timeout=15.0,
        )
        r.raise_for_status()
        rows = (r.json() or {}).get("data", []) or []
        return rows if isinstance(rows, list) else []
    except Exception as e:  # noqa: BLE001
        log.warning("spend: /activity fetch failed: %s", e)
        return []


def _row_date(row: dict) -> date | None:
    """Parse the row's `date` field (`"YYYY-MM-DD 00:00:00"`) into a UTC date."""
    raw = (row.get("date") or "").strip()
    if not raw:
        return None
    try:
        return datetime.strptime(raw[:10], "%Y-%m-%d").date()
    except ValueError:
        return None


# ─── state.db (non-OR sources only) ────────────────────────────────────────

def _query_today_or_sessions(today_cutoff: float) -> list[dict]:
    """Pull TODAY's OR-routed sessions from state.db as a partial-view
    fallback. OR's /activity has a multi-hour lag for the in-progress
    UTC day — per-row data for today often shows zero results until late
    in the day. state.db captures sessions when they end, so it has
    SOMETHING for today even if it undercounts (long sessions don't
    write back until they close). Caller adds a "partial" disclaimer.

    Anthropic-direct + custom rows are handled by `_query_non_or_sessions`
    regardless of date — they never appear in /activity at all."""
    if not STATE_DB.exists():
        return []
    try:
        conn = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True, timeout=2.0)
        conn.row_factory = sqlite3.Row
        cur = conn.execute(
            """
            SELECT model,
                   billing_provider,
                   COUNT(*)                                AS sessions,
                   SUM(input_tokens)                       AS p_tok,
                   SUM(output_tokens)                      AS c_tok,
                   COALESCE(SUM(estimated_cost_usd), 0)    AS est_cost,
                   MAX(started_at)                         AS last_seen
            FROM sessions
            WHERE started_at >= ?
              AND model IS NOT NULL AND model != ''
              AND LOWER(billing_provider) = 'openrouter'
            GROUP BY model, billing_provider
            ORDER BY est_cost DESC
            """,
            (today_cutoff,),
        )
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return rows
    except sqlite3.Error as e:
        log.warning("spend: state.db today-OR query failed: %s", e)
        return []


def _query_non_or_sessions(cutoff: float) -> list[dict]:
    """Pull `anthropic` (direct) and `custom` (local) sessions from
    state.db. OR-routed sessions are deliberately excluded — those are
    authoritative via /activity. Returns [] on DB error / DB missing."""
    if not STATE_DB.exists():
        return []
    try:
        conn = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True, timeout=2.0)
        conn.row_factory = sqlite3.Row
        cur = conn.execute(
            """
            SELECT model,
                   billing_provider,
                   COUNT(*)                                AS sessions,
                   SUM(input_tokens)                       AS p_tok,
                   SUM(output_tokens)                      AS c_tok,
                   COALESCE(SUM(estimated_cost_usd), 0)    AS est_cost,
                   MAX(started_at)                         AS last_seen
            FROM sessions
            WHERE started_at >= ?
              AND model IS NOT NULL AND model != ''
              AND LOWER(billing_provider) IN ('anthropic', 'custom')
            GROUP BY model, billing_provider
            ORDER BY est_cost DESC
            """,
            (cutoff,),
        )
        rows = [dict(r) for r in cur.fetchall()]
        conn.close()
        return rows
    except sqlite3.Error as e:
        log.warning("spend: state.db query failed: %s", e)
        return []


def _query_non_or_daily(cutoff: float) -> dict[str, float]:
    """Per-UTC-day cost for non-OR (anthropic-direct + custom) sessions.
    Custom rows zero out — the estimated_cost_usd column for local
    hardware is a hypothetical based on published prices, not money
    that actually changed hands."""
    if not STATE_DB.exists():
        return {}
    try:
        conn = sqlite3.connect(f"file:{STATE_DB}?mode=ro", uri=True, timeout=2.0)
        cur = conn.execute(
            """
            SELECT date(started_at, 'unixepoch', 'utc') AS day,
                   COALESCE(SUM(
                       CASE WHEN LOWER(billing_provider) = 'custom'
                            THEN 0
                            ELSE estimated_cost_usd END
                   ), 0) AS cost
            FROM sessions
            WHERE started_at >= ?
              AND model IS NOT NULL AND model != ''
              AND LOWER(billing_provider) IN ('anthropic', 'custom')
            GROUP BY day
            ORDER BY day
            """,
            (cutoff,),
        )
        out = {r[0]: float(r[1] or 0) for r in cur.fetchall() if r[0]}
        conn.close()
        return out
    except sqlite3.Error as e:
        log.warning("spend: state.db daily query failed: %s", e)
        return {}


# ─── Windowing + bucketing ─────────────────────────────────────────────────

def _window_bounds(window: str) -> tuple[date, date, str]:
    """Return (start_date_utc, end_date_utc, label). End is today UTC for
    every window — we want live in-progress data, not yesterday."""
    today_utc = datetime.now(timezone.utc).date()
    if window == "today":
        return today_utc, today_utc, "today (UTC, live)"
    if window == "month":
        return today_utc - timedelta(days=29), today_utc, "last 30 days"
    if window == "mtd":
        return today_utc.replace(day=1), today_utc, "month-to-date"
    return today_utc - timedelta(days=6), today_utc, "last 7 days"


def _bucket_or_row(row: dict) -> str:
    """Classify an OR /activity row by who actually pays. A single row
    can carry both OR-credit and BYOK pools if mixed-mode traffic
    happened that day for that endpoint, but we bucket by the dominant
    pool — caller passes each pool's cost separately so this matters
    only for label/display intent."""
    model = (row.get("model") or "").lower()
    if model.startswith("google/"):
        return "google (BYOK via OR)"
    if model.startswith("anthropic/"):
        return "anthropic (via OR credit)"
    return "openrouter credit"


def _bucket_state_row(row: dict) -> str:
    provider = (row.get("billing_provider") or "").lower()
    if provider == "custom":
        return "local (free)"
    if provider == "anthropic":
        return "anthropic (direct)"
    return provider or "unknown"


# ─── Aggregation ───────────────────────────────────────────────────────────

def _aggregate(
    or_rows: list[dict],
    state_rows: list[dict],
    state_daily: dict[str, float],
    today_or_rows: list[dict],
    credits_lifetime_usage: float,
    start: date,
    end: date,
) -> dict:
    """Walk both sources, filter to window, return aggregates ready for
    formatting.

    `today_or_rows` are state.db sessions with billing_provider='openrouter'
    that started during today UTC — used as a partial-view fallback while
    OR /activity catches up (multi-hour lag for the in-progress day).
    `credits_lifetime_usage` is the current /credits.total_usage, used to
    derive today's OR-credit dollar total as a delta against the historic
    /activity sum. The delta is authoritative for OR-credit (the endpoint
    is live); state.db gives the per-model breakdown."""
    by_model: dict[str, dict] = defaultdict(
        lambda: {"cost": 0.0, "calls": 0, "p_tok": 0, "c_tok": 0,
                 "bucket": "", "free": False}
    )
    by_bucket: dict[str, dict] = defaultdict(lambda: {"cost": 0.0, "calls": 0})
    daily: dict[str, float] = defaultdict(float)
    google_mtd_byok = 0.0  # MTD BYOK spend on google/* (not window-scoped)

    today_utc = datetime.now(timezone.utc).date()
    month_start = today_utc.replace(day=1)
    # Sum of OR-credit `usage` across ALL /activity rows hermes returns.
    # /activity goes up to yesterday-UTC; the difference between this and
    # /credits.total_usage is today's OR-credit dollars. We use that delta
    # to fill in today's OR-credit total when the window spans today.
    activity_or_credit_total = sum(float(r.get("usage") or 0) for r in or_rows)
    today_or_credit_delta = max(
        0.0, credits_lifetime_usage - activity_or_credit_total
    )
    today_partial = (start <= today_utc <= end)

    # OR rows — paid (OR credit) + BYOK (upstream account).
    for r in or_rows:
        d = _row_date(r)
        if d is None:
            continue
        model = r.get("model") or "(unknown)"
        or_cost = float(r.get("usage") or 0)
        byok_cost = float(r.get("byok_usage_inference") or 0)
        requests = int(r.get("requests") or 0)
        byok_reqs = int(r.get("byok_requests") or 0)
        or_reqs = max(0, requests - byok_reqs)
        p = int(r.get("prompt_tokens") or 0)
        c = int(r.get("completion_tokens") or 0)
        bucket = _bucket_or_row(r)

        # Google BYOK MTD — track regardless of requested window
        if (model or "").startswith("google/") and d >= month_start:
            google_mtd_byok += byok_cost

        if d < start or d > end:
            continue

        # Two pools per row, additive
        if or_cost > 0 or or_reqs > 0:
            m = by_model[model]
            m["cost"] += or_cost
            m["calls"] += or_reqs
            if requests > 0:
                share = or_reqs / requests
                m["p_tok"] += int(p * share)
                m["c_tok"] += int(c * share)
            m["bucket"] = bucket if not model.startswith("google/") else "openrouter credit"
            by_bucket[m["bucket"]]["cost"] += or_cost
            by_bucket[m["bucket"]]["calls"] += or_reqs
            daily[d.isoformat()] += or_cost

        if byok_cost > 0 or byok_reqs > 0:
            # BYOK pool gets its own line under a "<model> (BYOK)" key so
            # the by-model view doesn't conflate credit and BYOK spend.
            key = f"{model} (BYOK)" if or_cost > 0 else model
            m = by_model[key]
            m["cost"] += byok_cost
            m["calls"] += byok_reqs
            if requests > 0:
                share = byok_reqs / requests
                m["p_tok"] += int(p * share)
                m["c_tok"] += int(c * share)
            m["bucket"] = _bucket_or_row(r)  # google → google (BYOK via OR), etc.
            by_bucket[m["bucket"]]["cost"] += byok_cost
            by_bucket[m["bucket"]]["calls"] += byok_reqs
            daily[d.isoformat()] += byok_cost

    # state.db rows — anthropic direct + custom (local) only. These don't
    # carry a per-day breakdown so we attribute the whole window total to
    # the window's end date in `daily`. Good enough for the daily glance;
    # if it ever matters, we can pull individual session rows.
    for r in state_rows:
        provider = (r.get("billing_provider") or "").lower()
        is_free = provider == "custom"
        cost = 0.0 if is_free else float(r.get("est_cost") or 0)
        bucket = _bucket_state_row(r)
        model = r.get("model") or "(unknown)"
        m = by_model[model]
        m["cost"] += cost
        m["calls"] += int(r.get("sessions") or 0)
        m["p_tok"] += int(r.get("p_tok") or 0)
        m["c_tok"] += int(r.get("c_tok") or 0)
        m["bucket"] = bucket
        m["free"] = is_free
        by_bucket[bucket]["cost"] += cost
        by_bucket[bucket]["calls"] += int(r.get("sessions") or 0)

    # Today's partial view — only included when the window spans today.
    # state.db OR rows give per-model breakdown for sessions that have
    # ended; /credits delta covers the dollar total exactly. We surface
    # both: per-model rows show what hermes recorded (undercount likely),
    # and a synthetic "openrouter credit (today, /credits delta)" line
    # carries the true dollar total minus what state.db already attributed.
    if today_partial:
        today_iso = today_utc.isoformat()
        state_credit_today = 0.0
        for r in today_or_rows:
            model = r.get("model") or "(unknown)"
            cost = float(r.get("est_cost") or 0)
            calls = int(r.get("sessions") or 0)
            p = int(r.get("p_tok") or 0)
            c = int(r.get("c_tok") or 0)
            # state.db sessions are session-completion-gated. Tag the
            # rows so the by-model view shows they're partial.
            key = f"{model} _(today, partial)_"
            m = by_model[key]
            m["cost"] += cost
            m["calls"] += calls
            m["p_tok"] += p
            m["c_tok"] += c
            # We don't know if these specific sessions were OR-credit or
            # BYOK without parsing model name. Use the same prefix rule.
            if model.startswith("google/"):
                m["bucket"] = "google (BYOK via OR)"
            else:
                m["bucket"] = "openrouter credit"
                state_credit_today += cost
            by_bucket[m["bucket"]]["cost"] += cost
            by_bucket[m["bucket"]]["calls"] += calls
            daily[today_iso] += cost

        # Reconcile OR-credit total: the /credits delta is authoritative
        # for dollars. Subtract what state.db already counted to avoid
        # double-counting, then add the remainder as a single row.
        residual = today_or_credit_delta - state_credit_today
        if residual > 0.001:
            placeholder_key = "(other OR-credit today, no breakdown yet)"
            m = by_model[placeholder_key]
            m["cost"] += residual
            m["bucket"] = "openrouter credit"
            by_bucket["openrouter credit"]["cost"] += residual
            daily[today_iso] += residual

    # state.db daily breakdown — keyed by actual session start date so
    # the daily glance reflects when the Anthropic-direct calls really
    # happened, not the end of the requested window.
    start_iso = start.isoformat()
    end_iso = end.isoformat()
    for day, cost in state_daily.items():
        if start_iso <= day <= end_iso:
            daily[day] += cost

    return {
        "by_model": dict(by_model),
        "by_bucket": dict(by_bucket),
        "daily": dict(daily),
        "total_paid": sum(b["cost"] for b in by_bucket.values()),
        "google_mtd_byok": google_mtd_byok,
        "today_partial": today_partial,
        "today_or_credit_delta": today_or_credit_delta,
    }


# ─── Formatting ────────────────────────────────────────────────────────────

def _format_brief(
    label: str,
    start: date,
    end: date,
    agg: dict,
    credits: dict,
) -> str:
    lines: list[str] = []
    span_days = max(1, (end - start).days + 1)
    burn = agg["total_paid"] / span_days

    lines.append(
        f"💸 *Spend — {label}*  ({start.isoformat()} → {end.isoformat()} UTC)"
    )
    lines.append("_(OR /activity primary, state.db for non-OR; local = $0)_")
    if agg.get("today_partial"):
        lines.append(
            "_⚠ today's per-row breakdown lags OR /activity by a few hours;_"
        )
        lines.append(
            "_today's dollar total is exact (via /credits delta), but model attribution_"
        )
        lines.append(
            "_is partial — long sessions show up after they close (session-end gated)._"
        )
    lines.append("")

    # ─── OR balance ───
    total_credits = credits.get("total_credits")
    total_usage = credits.get("total_usage")
    remaining = credits.get("total_remaining")
    if remaining is None and total_credits is not None and total_usage is not None:
        remaining = float(total_credits) - float(total_usage)
    if remaining is not None:
        lines.append(
            f"🔵 *OpenRouter balance*  ${float(remaining):.2f} remaining  "
            f"_(${float(total_usage or 0):.2f} lifetime OR-credit; BYOK not counted)_"
        )
        lines.append("")

    # ─── Window total + per-provider rollup ───
    # Collapse the per-bucket detail into the three top-level destinations
    # that actually receive money: OR (deepseek + any anthropic-via-OR),
    # Google AI Studio (BYOK), Anthropic (direct API key). `local (free)`
    # is excluded from the total but listed for completeness.
    provider_totals = {"OpenRouter": 0.0, "Google AI Studio (BYOK)": 0.0,
                       "Anthropic (direct)": 0.0}
    for bucket, info in agg["by_bucket"].items():
        bl = bucket.lower()
        if "openrouter credit" in bl or "via or credit" in bl:
            provider_totals["OpenRouter"] += info["cost"]
        elif "google" in bl:
            provider_totals["Google AI Studio (BYOK)"] += info["cost"]
        elif "anthropic (direct)" in bl:
            provider_totals["Anthropic (direct)"] += info["cost"]
    nonzero_providers = [(k, v) for k, v in provider_totals.items() if v > 0]
    provider_label = " + ".join(k.split()[0] for k, _ in nonzero_providers) \
                     if nonzero_providers else "(nothing paid)"

    lines.append(
        f"*Total spend (paid)*: ${agg['total_paid']:.2f} across {provider_label}  "
        f"({span_days}d, burn ${burn:.2f}/d)"
    )
    for name, cost in sorted(nonzero_providers, key=lambda kv: -kv[1]):
        lines.append(f"  ${cost:>6.2f}  {name}")
    lines.append("")

    by_model = sorted(
        agg["by_model"].items(),
        key=lambda kv: -kv[1]["cost"],
    )

    if not by_model:
        lines.append("_(no activity in this window)_")
        lines.append("")
    else:
        lines.append("*By model*")
        for model, m in by_model[:10]:
            p_k = m["p_tok"] / 1000
            c_k = m["c_tok"] / 1000
            if m["free"]:
                cost_label = "free"
                tail = "  _local hardware — $0_"
            else:
                cost_label = f"${m['cost']:.3f}"
                tail = f"  _via {m['bucket']}_"
            lines.append(
                f"  {cost_label:>7}  {model}  "
                f"({m['calls']} req, {p_k:.0f}K in, {c_k:.0f}K out){tail}"
            )
        if len(by_model) > 10:
            lines.append(f"  _(+{len(by_model) - 10} more, hidden)_")
        lines.append("")

        # ─── By bucket ───
        lines.append("*By bill source*")
        buckets = sorted(agg["by_bucket"].items(), key=lambda kv: -kv[1]["cost"])
        for bucket, info in buckets:
            if "(free)" in bucket:
                lines.append(f"  {'free':>7}  {bucket}  ({info['calls']} req)")
            else:
                lines.append(f"  ${info['cost']:>6.3f}  {bucket}  ({info['calls']} req)")
        lines.append("")

    # ─── Google Pro budget ───
    g = agg["google_mtd_byok"]
    pct = (g / GOOGLE_PRO_MONTHLY_USD) * 100 if GOOGLE_PRO_MONTHLY_USD else 0
    bar_len = 20
    filled = min(bar_len, int(round(bar_len * pct / 100)))
    bar = "█" * filled + "░" * (bar_len - filled)
    lines.append(
        f"🟢 *Google Pro budget (MTD)*  ${g:.2f} / ${GOOGLE_PRO_MONTHLY_USD:.2f}  "
        f"({pct:.0f}%)"
    )
    lines.append(f"  `{bar}`")

    # ─── Daily ───
    if agg["daily"] and len(agg["daily"]) <= 10:
        lines.append("")
        lines.append("*Daily*")
        for day in sorted(agg["daily"]):
            lines.append(f"  {day}  ${agg['daily'][day]:.3f}")

    return "\n".join(lines)


# ─── Handler ───────────────────────────────────────────────────────────────

async def _run_spend(args: list[str]) -> str:
    window = "week"
    for a in args:
        if a in ("today", "week", "month", "mtd"):
            window = a
            break
    start, end, label = _window_bounds(window)
    # state.db cutoff in unix-seconds — UTC midnight of start date
    cutoff = datetime(
        start.year, start.month, start.day, tzinfo=timezone.utc
    ).timestamp()

    async with httpx.AsyncClient() as client:
        or_rows = await _fetch_activity(client)
        credits = await _fetch_credits(client)
    state_rows = _query_non_or_sessions(cutoff)
    state_daily = _query_non_or_daily(cutoff)
    # Today-OR fallback: state.db OR sessions that started today UTC.
    # Used for per-model partial view when window includes today.
    today_utc = datetime.now(timezone.utc).date()
    today_cutoff = datetime(
        today_utc.year, today_utc.month, today_utc.day, tzinfo=timezone.utc
    ).timestamp()
    today_or_rows = (
        _query_today_or_sessions(today_cutoff)
        if start <= today_utc <= end else []
    )
    credits_lifetime = float(credits.get("total_usage") or 0)
    agg = _aggregate(
        or_rows, state_rows, state_daily,
        today_or_rows, credits_lifetime,
        start, end,
    )
    log.info(
        "spend: window=%s or_rows=%d state_rows=%d total=$%.3f google_mtd=$%.3f",
        label, len(or_rows), len(state_rows), agg["total_paid"], agg["google_mtd_byok"],
    )
    return _format_brief(label, start, end, agg, credits)


async def _handle_slash(raw_args: str):
    args = raw_args.strip().lower().split()
    if any(a in ("help", "-h", "--help") for a in args):
        return (
            "/spend [today|week|month|mtd] — live spend from OpenRouter + hermes' state.db.\n"
            "  today           — current UTC day (live, partial)\n"
            "  week (default)  — last 7 UTC days\n"
            "  month           — last 30 UTC days\n"
            "  mtd             — month-to-date UTC\n"
            "\n"
            "Primary source: OR /activity (every OR-routed request, including\n"
            "BYOK Google via `byok_usage_inference`). Augmented with state.db\n"
            "for Anthropic-direct + local-Ollama sessions (never transit OR).\n"
            "`/credits` separate for runway/balance."
        )
    try:
        return await _run_spend(args)
    except Exception as e:  # noqa: BLE001
        log.exception("spend: failed")
        return f"spend error: {type(e).__name__}: {e}"


def register(ctx) -> None:
    ctx.register_command(
        "spend",
        handler=_handle_slash,
        description="Live per-model spend from OpenRouter + Pro-budget meter.",
        args_hint="[today|week|month|mtd]",
    )
