"""Red-team intel briefing plugin for hermes-agent.

Slash command: `/intel` → returns a categorized brief of the last 24h of
high-signal items from alex's Miniflux subscriptions, optimised for a
red-team operator's workflow.

Pipeline (all in-process, no MCPs):
  1. Pull last-24h unread entries from Miniflux's REST API.
  2. Triage every entry via Gemini Flash Lite (BYOK Gemini key on
     OpenRouter — effectively free). Drop non-English, score 0-3 for
     red-team relevance, classify into category.
  3. Filter to score >= 2, cap 5 entries per source feed (prevents one
     marketing-heavy blog from dominating).
  4. Take top 12 by score, fetch full content, synthesize via Gemini
     Flash Lite again. ~800-char Signal-friendly brief grouped by
     category.
  5. Mark briefed entries as read (skip with `/intel preview`).

Env requirements (set by hermes-agent.env template):
  - MINIFLUX_API_TOKEN  (sops:miniflux_api_token, alex-readable mode 0440)
  - OPENROUTER_API_KEY  (sops:openrouter_api_key, already in env)
"""

from __future__ import annotations

import json
import logging
import os
from collections import defaultdict
from datetime import datetime, timezone

import httpx

log = logging.getLogger("hermes.plugins.intel")

MINIFLUX_URL = os.environ.get("MINIFLUX_URL", "http://10.1.8.121:8080")
MINIFLUX_TIMEOUT = 20.0
OPENROUTER_URL = "https://openrouter.ai/api/v1/chat/completions"
TRIAGE_MODEL = "google/gemini-2.5-flash-lite"
SYNTH_MODEL = "google/gemini-2.5-flash-lite"

PER_FEED_CAP = 5
SCORE_THRESHOLD = 2
TOP_N_FOR_SYNTH = 12
SNIPPET_CHARS = 300
WINDOW_SECONDS = 24 * 60 * 60

TRIAGE_SYSTEM = """You triage entries from a red-team operator's RSS feed.

For EACH entry below, return one JSON object on its own line with these fields:
  id        — the entry id (integer, unchanged from input)
  score     — 0,1,2,3 (see scale below)
  language  — "en" or "other"
  category  — one of: cve, tooling, apt, advisory, opsec, defense, research, noise

Score scale (red-team operator perspective):
  3 = directly useful right now: new exploit, weaponized PoC, novel TTP,
      bypass for common defenses, fresh CVE in commonly-engaged software
  2 = useful adjacent context: vendor advisory worth knowing, APT
      campaign analysis, research drop with operational implications
  1 = peripheral awareness only: general security news, conference
      announcements, retrospectives
  0 = noise: marketing fluff, consultancy filler, vendor PR, generic
      "why pentesting matters" content, listicles

LANGUAGE RULE: If the entry is NOT in English, set score=0 regardless of
content. Set language="other" on those.

Return ONLY a JSON array of objects. No prose, no markdown fences.
"""

SYNTH_SYSTEM = """You are briefing a red-team operator on the past 24
hours of intel. The entries you receive have already been filtered for
relevance — your job is synthesis, not further filtering.

Output format (markdown, ~1000 chars total, Signal-friendly):

  *<CATEGORY UPPER>*
  • <one-line takeaway>. _Offense angle:_ <one line>.
  • <next item>...

  *<NEXT CATEGORY>*
  ...

  *🎬 SHORT-FORM CONTENT IDEAS*
  • _<entry title>_ — <one-line angle for a tweet thread / 60-90s video>.
  • _<entry title>_ — <angle>.

Rules:
- Group items by category (cve, tooling, apt, advisory, opsec, defense,
  research). Order categories by operator value: cve, tooling, apt,
  advisory, opsec, defense, research.
- Skip categories with no items.
- Each item: takeaway is the WHAT, offense angle is the SO-WHAT. Keep
  both tight — one sentence each, no fluff.
- Do NOT include the entry URL or feed name; the user can drill down in
  Miniflux if they want.
- Do NOT add a preamble, intro line, or closing summary. Start directly
  with the first category header.

SHORT-FORM CONTENT IDEAS — append this section ONLY if you find 1-3
entries from this batch that would make compelling short-form content
(X/Twitter thread, LinkedIn post, 60-90s video) for a red-team operator's
audience. Criteria for selection:
  • Tight standalone hook (one-liner that pulls attention)
  • Visual or demonstrable (a screenshot, command sequence, or before/after)
  • Recency matters (people care about THIS week)
  • Original takeaway possible (not just regurgitating the source)
If nothing in the batch fits, OMIT the section entirely — do not force it.
For each idea: italicize the source entry title (`_title_`) and give a
ONE-sentence angle that frames how the operator would pitch it. No fluff.
"""


def _miniflux_headers() -> dict:
    token = os.environ.get("MINIFLUX_API_TOKEN")
    if not token:
        raise RuntimeError("MINIFLUX_API_TOKEN not set in environment")
    return {"X-Auth-Token": token}


def _openrouter_headers() -> dict:
    key = os.environ.get("OPENROUTER_API_KEY")
    if not key:
        raise RuntimeError("OPENROUTER_API_KEY not set in environment")
    return {
        "Authorization": f"Bearer {key}",
        "Content-Type": "application/json",
        # OR's BYOK Gemini routing only activates when the request
        # specifies a Google-family model AND the account has BYOK set
        # up (alex did this in the OR UI). Nothing extra needed in the
        # request body.
    }


async def _fetch_recent_entries(client: httpx.AsyncClient) -> list[dict]:
    """Pull all entries published in the last 24 h, unread only."""
    after = int(datetime.now(timezone.utc).timestamp()) - WINDOW_SECONDS
    # limit=500 — miniflux caps at this. If alex ever produces >500
    # entries/day we'll need pagination; today's volume is ~110.
    r = await client.get(
        f"{MINIFLUX_URL}/v1/entries",
        params={
            "published_after": after,
            "status": "unread",
            "limit": 500,
            "order": "published_at",
            "direction": "desc",
        },
        headers=_miniflux_headers(),
        timeout=MINIFLUX_TIMEOUT,
    )
    r.raise_for_status()
    return r.json().get("entries", [])


async def _mark_entries_read(client: httpx.AsyncClient, ids: list[int]) -> None:
    if not ids:
        return
    r = await client.put(
        f"{MINIFLUX_URL}/v1/entries",
        json={"entry_ids": ids, "status": "read"},
        headers=_miniflux_headers(),
        timeout=MINIFLUX_TIMEOUT,
    )
    r.raise_for_status()


async def _call_openrouter(
    client: httpx.AsyncClient, model: str, system: str, user: str
) -> str:
    r = await client.post(
        OPENROUTER_URL,
        headers=_openrouter_headers(),
        json={
            "model": model,
            "messages": [
                {"role": "system", "content": system},
                {"role": "user", "content": user},
            ],
            "temperature": 0.0,
        },
        timeout=120.0,
    )
    r.raise_for_status()
    return r.json()["choices"][0]["message"]["content"]


def _build_triage_payload(entries: list[dict]) -> str:
    """Pack entries into a compact form for the triage model — id, feed
    name, title, short snippet from the body. We do not send full
    content here; the goal is breadth-with-low-cost, depth comes in the
    synth pass.
    """
    rows = []
    for e in entries:
        content = (e.get("content") or "").strip()
        # Cheap HTML-tag strip — good enough for a snippet, not for
        # rendering. The triage model handles residual noise fine.
        if "<" in content:
            import re
            content = re.sub(r"<[^>]+>", " ", content)
            content = re.sub(r"\s+", " ", content).strip()
        rows.append({
            "id": e["id"],
            "feed": (e.get("feed") or {}).get("title", ""),
            "title": e.get("title", ""),
            "snippet": content[:SNIPPET_CHARS],
        })
    return json.dumps(rows, ensure_ascii=False)


def _parse_triage_response(raw: str) -> list[dict]:
    """Robustly parse the triage model's output. We've observed Gemini
    Flash Lite return three shapes despite identical instructions:
      1. A clean JSON array  — `[{...}, {...}]`
      2. Markdown-fenced JSON array  — ```json\n[...]\n```
      3. JSONL inside a markdown fence  — ```json\n{...}\n{...}\n```
    Try array first, fall back to line-by-line JSON object parsing.
    """
    s = raw.strip()
    # Strip an optional markdown fence (```json...``` or ```...```).
    if s.startswith("```"):
        # Drop the opening fence line.
        s = s.split("\n", 1)[1] if "\n" in s else s[3:]
        # Drop the trailing fence if present.
        if s.rstrip().endswith("```"):
            s = s.rstrip()[:-3]
    s = s.strip()

    # Form 1/2 — single JSON value (likely a list).
    try:
        out = json.loads(s)
        if isinstance(out, list):
            return out
        if isinstance(out, dict):
            return [out]
    except json.JSONDecodeError:
        pass

    # Form 3 — JSONL. Parse each non-blank line independently and tolerate
    # the occasional malformed one rather than dropping the whole batch.
    out_list: list[dict] = []
    for line in s.splitlines():
        line = line.strip().rstrip(",")
        if not line or line in ("[", "]"):
            continue
        try:
            obj = json.loads(line)
        except json.JSONDecodeError:
            continue
        if isinstance(obj, dict):
            out_list.append(obj)
    if out_list:
        return out_list

    log.warning("triage parse failed entirely; raw[:200]=%r", raw[:200])
    return []


def _filter_and_dedupe(
    entries: list[dict], triage: list[dict]
) -> list[dict]:
    """Apply: english-only, score >= threshold, then cap per-feed to
    prevent a single noisy source from dominating.
    """
    by_id = {e["id"]: e for e in entries}
    survivors: list[dict] = []
    for t in triage:
        eid = t.get("id")
        if eid not in by_id:
            continue
        if t.get("language") != "en":
            continue
        score = t.get("score", 0)
        if not isinstance(score, (int, float)) or score < SCORE_THRESHOLD:
            continue
        entry = by_id[eid]
        survivors.append({
            "id": eid,
            "score": score,
            "category": t.get("category", "research"),
            "title": entry.get("title", ""),
            "feed_id": entry.get("feed_id"),
            "feed_title": (entry.get("feed") or {}).get("title", ""),
            "content": entry.get("content", ""),
            "url": entry.get("url", ""),
        })

    # Per-feed cap. Sort by score first so the survivors we keep from
    # each feed are its best, not its earliest.
    survivors.sort(key=lambda x: -x["score"])
    per_feed: dict[int, int] = defaultdict(int)
    capped: list[dict] = []
    for s in survivors:
        fid = s["feed_id"]
        if per_feed[fid] >= PER_FEED_CAP:
            continue
        per_feed[fid] += 1
        capped.append(s)
    return capped


def _strip_html(s: str) -> str:
    import re
    s = re.sub(r"<[^>]+>", " ", s or "")
    return re.sub(r"\s+", " ", s).strip()


def _build_synth_payload(survivors: list[dict]) -> str:
    """For the synthesis pass: send full content (HTML-stripped) of the
    top survivors. Pre-grouped by category to nudge the model toward
    the expected output structure.
    """
    by_cat: dict[str, list[dict]] = defaultdict(list)
    for s in survivors:
        by_cat[s["category"]].append(s)

    lines = []
    for cat in sorted(by_cat):
        lines.append(f"=== category: {cat} ===")
        for s in by_cat[cat]:
            lines.append(f"\n--- score={s['score']} title={s['title']!r} ---")
            lines.append(_strip_html(s["content"])[:4000])
    return "\n".join(lines)


async def _run_intel(preview: bool) -> str:
    async with httpx.AsyncClient() as client:
        entries = await _fetch_recent_entries(client)
        if not entries:
            return "No new entries in the last 24h."

        log.info("intel: fetched %d entries", len(entries))
        triage_raw = await _call_openrouter(
            client, TRIAGE_MODEL, TRIAGE_SYSTEM, _build_triage_payload(entries)
        )
        triage = _parse_triage_response(triage_raw)
        log.info("intel: triage returned %d scored entries", len(triage))

        survivors = _filter_and_dedupe(entries, triage)
        log.info("intel: %d entries survived filtering", len(survivors))

        if not survivors:
            return (
                f"Triaged {len(entries)} entries — none cleared the relevance "
                "threshold. Mostly noise / non-English / consultancy filler today."
            )

        top = survivors[:TOP_N_FOR_SYNTH]
        brief = await _call_openrouter(
            client, SYNTH_MODEL, SYNTH_SYSTEM, _build_synth_payload(top)
        )

        if not preview:
            await _mark_entries_read(client, [s["id"] for s in survivors])

        # Header line is for alex's situational awareness; the model's
        # output starts on the next line.
        header = (
            f"📡 *Intel — last 24h* — "
            f"{len(entries)} entries → {len(survivors)} kept → top {len(top)} below"
            + ("  _(preview, none marked read)_" if preview else "")
        )
        return f"{header}\n\n{brief.strip()}"


async def _handle_slash(raw_args: str):
    args = raw_args.strip().lower().split()
    preview = "preview" in args
    if any(a in ("help", "-h", "--help") for a in args):
        return (
            "/intel — brief on last 24h of red-team RSS.\n"
            "/intel preview — same, but don't mark entries read."
        )
    try:
        return await _run_intel(preview=preview)
    except httpx.HTTPStatusError as e:
        log.exception("intel: upstream HTTP error")
        return f"intel error: {e.response.status_code} from {e.request.url.host}"
    except Exception as e:  # noqa: BLE001
        log.exception("intel: unexpected failure")
        return f"intel error: {type(e).__name__}: {e}"


def register(ctx) -> None:
    ctx.register_command(
        "intel",
        handler=_handle_slash,
        description="Red-team intel briefing — last 24h, filtered + categorised.",
        args_hint="[preview]",
    )
