"""Spend tracker plugin for hermes-agent.

Slash command: `/spend [today|week|month|mtd]`

Pulls all of alex's metered LLM spend from a single source — OpenRouter's
`/credits` and `/activity` endpoints. Three sections of breakdown:

  • OpenRouter direct — real $ off OR credit balance, per model
  • Anthropic via OR — Opus / Sonnet pass-through that already lives in
    the OR total above, broken out for visibility
  • Google BYOK — token counts × Google's published per-model price
    (since BYOK calls cost $0 on OR but bill against the Google account)

claude-code is a flat monthly subscription, not metered — explicitly
called out as such in the brief so it isn't a blind spot.

No new secrets. No new infrastructure. Reuses the existing
OPENROUTER_API_KEY from hermes-agent's env. ~150 LOC of plumbing.
"""

from __future__ import annotations

import asyncio
import logging
import os
from collections import defaultdict
from datetime import date, datetime, timedelta

import httpx

log = logging.getLogger("hermes.plugins.spend")

OPENROUTER_API_URL = "https://openrouter.ai/api/v1"

# OR's /activity rows expose BYOK cost directly via
# `byok_usage_inference` (computed by OR against the upstream's
# actual prices). No need to hand-maintain a price table here — OR
# does the math.

# Concurrency cap on per-day /activity fetches. OR's rate ceiling is
# ~10 req/s for inferred-key holders; 5 in parallel keeps us safely
# under that even with multiple users hitting the API.
ACTIVITY_FETCH_PARALLEL = 5


# ─── HTTP helpers ───────────────────────────────────────────────────────────

PLACEHOLDER_SIGIL = "PLACEHOLDER_REPLACE_VIA_SOPS_EDIT"


def _provisioning_key() -> str | None:
    """Returns the OR provisioning (management) key if it's set to a
    real value, or None if it's the unfilled placeholder. Plugin
    callers can use this to decide whether to attempt /activity
    reads (which require the management key) or skip the section.
    """
    k = os.environ.get("OPENROUTER_PROVISIONING_KEY", "")
    if not k or k == PLACEHOLDER_SIGIL:
        return None
    return k


async def _or_get(
    client: httpx.AsyncClient, path: str, key: str
) -> dict:
    r = await client.get(
        f"{OPENROUTER_API_URL}{path}",
        headers={"Authorization": f"Bearer {key}"},
        timeout=20.0,
    )
    r.raise_for_status()
    return r.json()


async def _fetch_credits(client: httpx.AsyncClient) -> dict:
    """Lifetime totals: total_credits purchased, total_usage consumed.
    The inference key is authorized for this endpoint — no need to
    burn the provisioning key on a read that the cheap one handles.
    """
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        return {}
    try:
        d = (await _or_get(client, "/credits", key)).get("data", {}) or {}
    except Exception as e:  # noqa: BLE001
        log.warning("spend: /credits fetch failed: %s", e)
        return {}
    return d


async def _fetch_activity_day(
    client: httpx.AsyncClient, d: date, sem: asyncio.Semaphore, mgmt_key: str
) -> list[dict]:
    """One day's worth of per-request activity rows. /activity requires
    the OR provisioning key — the runtime inference key returns 403.
    Returns [] on failure rather than raising — losing a single day's
    data shouldn't poison the whole report.
    """
    async with sem:
        try:
            data = await _or_get(client, f"/activity?date={d.isoformat()}", mgmt_key)
        except httpx.HTTPStatusError as e:
            # 400 = date not yet completed (today UTC). Quiet skip.
            if e.response.status_code == 400:
                return []
            log.warning(
                "spend: /activity %s HTTP %d: %s",
                d, e.response.status_code, e.response.text[:200],
            )
            return []
        except Exception as e:  # noqa: BLE001
            log.warning("spend: /activity for %s failed: %s", d, e)
            return []
    rows = data.get("data", [])
    return rows if isinstance(rows, list) else []


# ─── Aggregation ────────────────────────────────────────────────────────────

# BYOK signal is two fields on the OR row:
#   byok_requests          → count of requests in this row that went BYOK
#   byok_usage_inference   → cost already computed by OR against the
#                            upstream's actual prices (Google or Anthropic).
# A row may be mixed: some BYOK + some non-BYOK. We treat the two
# spend pools as additive: `usage` is OR-credit spend, `byok_usage_inference`
# is upstream-account spend.


def _parse_window(args: list[str]) -> tuple[date, date, str]:
    """OR's /activity endpoint only serves *completed UTC days* — today
    UTC is always a 400 error until UTC midnight passes. So "today"
    here means "the most recent completed UTC day", which for users
    west of UTC is what they'd call yesterday after a normal morning.

    All windows end at this `latest_available`, never at the wall-clock
    today, so the user never gets a confusing empty result for the
    in-progress day.
    """
    today_utc = datetime.utcnow().date()
    latest_available = today_utc - timedelta(days=1)
    if "today" in args:
        return latest_available, latest_available, "yesterday (UTC, latest completed)"
    if "month" in args:
        return latest_available - timedelta(days=29), latest_available, "last 30 days"
    if "mtd" in args:
        # Month-to-date through the latest completed UTC day.
        return today_utc.replace(day=1), latest_available, "month-to-date"
    # default + explicit "week"
    return latest_available - timedelta(days=6), latest_available, "last 7 days"


def _aggregate(rows: list[dict]) -> dict:
    """Walk every activity row and aggregate three spend pools:

      or_direct       {model: {"cost", "calls", "p_tok", "c_tok"}}
                      — non-BYOK requests, billed to OR credit
      byok_by_model   {model: {"cost", "calls", "p_tok", "c_tok"}}
                      — BYOK requests, billed to upstream account
      anthropic_via   {model: cost}  — subset of or_direct for
                      the "via-OR-passthrough" clarifier section

    A single row can contribute to BOTH or_direct AND byok if it
    mixed BYOK + non-BYOK requests in the same day; the field names
    `usage` and `byok_usage_inference` are independent pools.
    """
    or_direct: dict[str, dict] = defaultdict(
        lambda: {"cost": 0.0, "calls": 0, "p_tok": 0, "c_tok": 0}
    )
    byok_by_model: dict[str, dict] = defaultdict(
        lambda: {"cost": 0.0, "calls": 0, "p_tok": 0, "c_tok": 0}
    )
    anthropic_via: dict[str, float] = defaultdict(float)

    for r in rows:
        model = r.get("model") or "(unknown)"
        or_cost = float(r.get("usage", 0) or 0)
        byok_cost = float(r.get("byok_usage_inference", 0) or 0)
        total_requests = int(r.get("requests", 0) or 0)
        byok_requests = int(r.get("byok_requests", 0) or 0)
        non_byok_requests = max(0, total_requests - byok_requests)
        p = int(r.get("prompt_tokens", 0) or 0)
        c = int(r.get("completion_tokens", 0) or 0)

        if non_byok_requests > 0 or or_cost > 0:
            or_direct[model]["cost"] += or_cost
            or_direct[model]["calls"] += non_byok_requests
            # Token attribution is approximate when a row mixes BYOK +
            # non-BYOK — OR doesn't split tokens by path. Pro-rate by
            # request share; better than dropping the data entirely.
            if total_requests > 0:
                share = non_byok_requests / total_requests
                or_direct[model]["p_tok"] += int(p * share)
                or_direct[model]["c_tok"] += int(c * share)
            if model.startswith("anthropic/"):
                anthropic_via[model] += or_cost

        if byok_requests > 0 or byok_cost > 0:
            byok_by_model[model]["cost"] += byok_cost
            byok_by_model[model]["calls"] += byok_requests
            if total_requests > 0:
                share = byok_requests / total_requests
                byok_by_model[model]["p_tok"] += int(p * share)
                byok_by_model[model]["c_tok"] += int(c * share)

    return {
        "or_direct": dict(or_direct),
        "byok_by_model": dict(byok_by_model),
        "anthropic_via": dict(anthropic_via),
        "totals": {
            "or_real": sum(s["cost"] for s in or_direct.values()),
            "byok_total": sum(s["cost"] for s in byok_by_model.values()),
            "anthropic": sum(anthropic_via.values()),
        },
    }


# ─── Formatting ─────────────────────────────────────────────────────────────

def _format_brief(
    window_label: str,
    start: date,
    end: date,
    days: int,
    credits: dict,
    agg: dict,
    has_mgmt: bool,
) -> str:
    lines: list[str] = []
    lines.append(
        f"💸 *Spend — {window_label}*  ({start.isoformat()} → {end.isoformat()})"
    )
    lines.append("")

    # ─── OpenRouter ───
    or_real = agg["totals"]["or_real"]
    total_credits = credits.get("total_credits")
    total_usage = credits.get("total_usage")
    remaining = credits.get("total_remaining")
    if remaining is None and total_credits is not None and total_usage is not None:
        remaining = float(total_credits) - float(total_usage)

    lines.append("🔵 *OpenRouter*")
    if not has_mgmt:
        lines.append(
            "  _⚠ per-model breakdown disabled — set "
            "openrouter_provisioning_key in sops to enable._"
        )
    if remaining is not None:
        lines.append(
            f"  ${or_real:.2f} spent  |  ${remaining:.2f} remaining"
        )
        if or_real > 0 and days > 0:
            burn = or_real / days
            runway = remaining / burn if burn > 0 else None
            runway_part = f"  |  ~{runway:.0f}d runway" if runway else ""
            lines.append(f"  burn ${burn:.2f}/day{runway_part}")
    else:
        lines.append(f"  ${or_real:.2f} spent in window")

    or_by_model = sorted(
        agg["or_direct"].items(), key=lambda kv: -kv[1]["cost"]
    )
    shown = [(m, s) for m, s in or_by_model if s["cost"] > 0][:8]
    for model, stats in shown:
        lines.append(
            f"  ${stats['cost']:>6.3f}  {model}  ({stats['calls']} calls)"
        )
    if not shown:
        lines.append("  _(no metered OR activity in this window)_")
    lines.append("")

    # ─── Anthropic-via-OR clarifier ───
    anthropic_total = agg["totals"]["anthropic"]
    if anthropic_total > 0:
        lines.append("🟡 *Anthropic* (via OR pass-through — already in OR total)")
        for model, cost in sorted(
            agg["anthropic_via"].items(), key=lambda kv: -kv[1]
        ):
            lines.append(f"  ${cost:>6.3f}  {model}")
        lines.append("")

    # ─── BYOK breakdown (Google + Anthropic + other) ───
    # Split by upstream provider so the user sees Google BYOK separately
    # from Anthropic BYOK if both are configured.
    byok = agg["byok_by_model"]
    if byok:
        google_byok = {m: s for m, s in byok.items() if m.startswith("google/")}
        anthropic_byok = {m: s for m, s in byok.items() if m.startswith("anthropic/")}
        other_byok = {
            m: s for m, s in byok.items()
            if not (m.startswith("google/") or m.startswith("anthropic/"))
        }

        def _byok_section(title: str, emoji: str, group: dict) -> None:
            if not group:
                return
            total = sum(s["cost"] for s in group.values())
            lines.append(f"{emoji} *{title} (BYOK)*  ${total:.3f}")
            for model, stats in sorted(group.items(), key=lambda kv: -kv[1]["cost"]):
                p_k = stats["p_tok"] / 1000
                c_k = stats["c_tok"] / 1000
                lines.append(
                    f"  ${stats['cost']:>6.3f}  {model}  "
                    f"({p_k:.0f}K in, {c_k:.0f}K out, {stats['calls']} calls)"
                )
            lines.append("")

        _byok_section("Google", "🟢", google_byok)
        _byok_section("Anthropic", "🟣", anthropic_byok)
        _byok_section("Other", "⚫", other_byok)

    # ─── Final total ───
    byok_total = agg["totals"]["byok_total"]
    lines.append("")
    lines.append(
        f"*Total metered ({window_label})*: ${or_real:.2f} OR"
        + (f"  +  ${byok_total:.2f} BYOK upstream" if byok_total > 0 else "")
    )
    return "\n".join(lines)


# ─── Handler ────────────────────────────────────────────────────────────────

async def _run_spend(window_args: list[str]) -> str:
    start, end, label = _parse_window(window_args)
    days = (end - start).days + 1
    date_range = [start + timedelta(days=i) for i in range(days)]
    mgmt_key = _provisioning_key()

    sem = asyncio.Semaphore(ACTIVITY_FETCH_PARALLEL)
    async with httpx.AsyncClient() as client:
        if mgmt_key:
            credits, *activity_per_day = await asyncio.gather(
                _fetch_credits(client),
                *[_fetch_activity_day(client, d, sem, mgmt_key) for d in date_range],
            )
            all_rows: list[dict] = []
            for day_rows in activity_per_day:
                all_rows.extend(day_rows)
        else:
            credits = await _fetch_credits(client)
            all_rows = []
    log.info(
        "spend: window=%s days=%d rows=%d mgmt_key=%s",
        label, days, len(all_rows), bool(mgmt_key),
    )
    agg = _aggregate(all_rows)
    return _format_brief(label, start, end, days, credits, agg, has_mgmt=bool(mgmt_key))


async def _handle_slash(raw_args: str):
    args = raw_args.strip().lower().split()
    if any(a in ("help", "-h", "--help") for a in args):
        return (
            "/spend [today|week|month|mtd] — spending across OpenRouter.\n"
            "  week  (default) — last 7 days\n"
            "  today           — today only\n"
            "  month           — last 30 days\n"
            "  mtd             — month-to-date\n"
            "Anthropic spend appears via OR pass-through; Google BYOK\n"
            "consumption comes from OR's own per-row byok_usage_inference."
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
        description="OR credit balance + per-model spend + Google BYOK estimate.",
        args_hint="[today|week|month|mtd]",
    )
