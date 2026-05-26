"""Vault indexer: reconciles an Obsidian vault directory into agent_memory.

For every Markdown file under the vault root, splits the file into chunks
by Markdown header (H1/H2/H3) with a per-chunk token budget (~500 tokens).
Each chunk is inserted into agent_memory under project='vault' with
source='vault:<relative path>#<heading-anchor>' and metadata.sha256 of the
chunk content. On subsequent runs, chunks whose sha256 hasn't changed are
skipped; changed chunks are deleted + re-inserted; orphaned rows (the
note no longer exists on disk, or the heading was renamed) are removed.

Driven by a systemd timer. Designed to be a one-way mirror — the LLM
never writes back to the vault from agent_memory (vault-mcp does that
separately, behind its own auth).

Talks to agent-memory-mcp over HTTP with a bearer token. Reads vault
files directly off disk (service user must have read access).
"""

from __future__ import annotations

import asyncio
import hashlib
import json
import logging
import os
import re
import sys
from contextlib import asynccontextmanager
from importlib.metadata import PackageNotFoundError, version as _pkg_version
from pathlib import Path
from typing import Any

try:
    __version__ = _pkg_version("vault-indexer")
except PackageNotFoundError:
    __version__ = "0.0.0-dev"

import httpx
from mcp import ClientSession
from mcp.client.streamable_http import streamablehttp_client

log = logging.getLogger("vault_indexer")

# Skip these top-level dirs and any dotfile in general.
SKIP_PREFIXES = (".obsidian", ".trash", ".git")
TEXT_EXTENSIONS = (".md",)
# Rough token estimate: ~4 chars per token. Cap chunks at 500 tokens.
MAX_CHARS_PER_CHUNK = 2000
HEADING_RE = re.compile(r"^(#{1,3})\s+(.+?)\s*$")


# ── chunking ────────────────────────────────────────────────────────────────

def slugify(s: str) -> str:
    """Make a heading-anchor-safe slug for use in the source key."""
    s = re.sub(r"[^A-Za-z0-9\s-]", "", s)
    s = re.sub(r"\s+", "-", s.strip())
    return s.lower()[:80] or "section"


def chunk_markdown(text: str) -> list[tuple[str, str]]:
    """Split a Markdown document into (heading_slug, chunk_text) pairs.

    Strategy:
      1. Walk lines; whenever a #/##/### heading is hit, start a new section.
      2. Content before the first heading goes under slug='preamble'.
      3. If a section exceeds MAX_CHARS_PER_CHUNK, split it into N parts
         with suffixes '#part1', '#part2', etc.
    """
    sections: list[tuple[str, list[str]]] = []
    current_heading = "preamble"
    current_buf: list[str] = []
    for line in text.splitlines():
        m = HEADING_RE.match(line)
        if m:
            if current_buf:
                sections.append((current_heading, current_buf))
            current_heading = slugify(m.group(2))
            current_buf = [line]
        else:
            current_buf.append(line)
    if current_buf:
        sections.append((current_heading, current_buf))

    chunks: list[tuple[str, str]] = []
    for slug, lines in sections:
        body = "\n".join(lines).strip()
        if not body:
            continue
        if len(body) <= MAX_CHARS_PER_CHUNK:
            chunks.append((slug, body))
            continue
        # Split oversize sections into roughly-equal parts on paragraph
        # boundaries when possible. Suffix with #part<N>.
        paragraphs = body.split("\n\n")
        buf = ""
        part = 1
        for p in paragraphs:
            # A single paragraph can already exceed the budget (e.g., a big
            # YAML block or a wall of code with no blank lines). Hard-split
            # such giants on a character boundary; that's worse for retrieval
            # locally but prevents the embedding service from rejecting the
            # whole job. The split is deterministic so re-runs hit cache.
            if len(p) > MAX_CHARS_PER_CHUNK:
                if buf.strip():
                    chunks.append((f"{slug}#part{part}", buf.strip()))
                    part += 1
                    buf = ""
                for hard in _hard_split(p, MAX_CHARS_PER_CHUNK):
                    chunks.append((f"{slug}#part{part}", hard))
                    part += 1
                continue
            if buf and len(buf) + len(p) + 2 > MAX_CHARS_PER_CHUNK:
                chunks.append((f"{slug}#part{part}", buf.strip()))
                buf = p
                part += 1
            else:
                buf = (buf + "\n\n" + p) if buf else p
        if buf.strip():
            chunks.append((f"{slug}#part{part}" if part > 1 else slug, buf.strip()))
    return chunks


def _hard_split(text: str, max_chars: int) -> list[str]:
    """Split a string into chunks no larger than `max_chars`, preferring to
    break on whitespace/newline boundaries near the cap so words stay intact
    where possible. Falls back to a hard character cut if no whitespace is
    found in the window.
    """
    pieces: list[str] = []
    i = 0
    n = len(text)
    while i < n:
        end = min(i + max_chars, n)
        if end < n:
            # Try to back off to the last whitespace within the last 10% of
            # the window so we don't cut a token in half. If none, hard-cut.
            window_start = max(i + int(max_chars * 0.9), i + 1)
            cut = text.rfind("\n", window_start, end)
            if cut == -1:
                cut = text.rfind(" ", window_start, end)
            if cut != -1:
                end = cut
        pieces.append(text[i:end].strip())
        i = end
    return [p for p in pieces if p]


def iter_notes(vault_root: Path):
    """Yield Path objects for every Markdown file under the vault root,
    skipping dotfiles and the .obsidian/.trash/.git roots."""
    for p in vault_root.rglob("*"):
        if not p.is_file():
            continue
        rel_parts = p.relative_to(vault_root).parts
        if any(part.startswith(".") for part in rel_parts):
            continue
        if rel_parts and rel_parts[0] in SKIP_PREFIXES:
            continue
        if p.suffix.lower() in TEXT_EXTENSIONS:
            yield p


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


# ── agent-memory client wrapper ─────────────────────────────────────────────

@asynccontextmanager
async def open_session(url: str, bearer: str):
    headers = {"Authorization": f"Bearer {bearer}"}
    async with streamablehttp_client(url, headers=headers) as (read, write, _close):
        async with ClientSession(read, write) as session:
            await session.initialize()
            yield session


async def call_tool(session: ClientSession, name: str, args: dict[str, Any]) -> Any:
    result = await session.call_tool(name, args)
    if result.isError:
        text = " ".join(getattr(b, "text", "") for b in result.content)
        raise RuntimeError(f"tool {name} failed: {text}")
    # Most tools return a structuredContent with `result` or a single dict.
    if result.structuredContent is not None:
        sc = result.structuredContent
        return sc.get("result", sc)
    # Fallback: concat text blocks.
    return " ".join(getattr(b, "text", "") for b in result.content)


# ── main reconciliation ────────────────────────────────────────────────────

async def reconcile(vault_root: Path, am_url: str, bearer: str) -> None:
    async with open_session(am_url, bearer) as session:
        # 1. Snapshot existing vault: rows in agent_memory under source LIKE 'vault:%'.
        # Explicit large limit overrides memory_list_by_source's default cap of
        # 10 000. Without this, snapshots are silently truncated once the vault
        # exceeds ~10k chunks — any source past the cap is treated as missing
        # by the sha-skip check below, gets re-inserted every hour, and the
        # table grows exponentially. Observed 2026-05-26: 12.7k unique sources
        # multiplied to 4.1M rows (~325× duplication) before postgres ran out
        # of disk. 1M is comfortable headroom for years of vault growth.
        existing = await call_tool(
            session,
            "memory_list_by_source",
            {"source_prefix": "vault:", "limit": 1_000_000},
        )
        # Build by_source as a list-valued map first, so we can detect any
        # surviving duplicates from before the schema's UNIQUE INDEX landed.
        # In steady state every list has exactly one entry; if any have more,
        # the indexer cleans them up by deleting the older rows and proceeds
        # with the newest. Observed 2026-05-26: a partial-crashed run seeded
        # ~1115 duplicates that the Python dict comprehension's last-write-
        # wins semantics couldn't surface (each indexer run only deleted one
        # dup row at a time, perpetuating the rest). Belt-and-suspenders to
        # the schema constraint, mostly defensive.
        by_source_lists: dict[str, list[dict[str, Any]]] = {}
        for row in (existing or []):
            by_source_lists.setdefault(row["source"], []).append(row)

        # The Go MCP's memory_list_by_source orders by (source, created_at DESC)
        # so the first row of each list is already the newest. Defensive cleanup
        # of any stragglers — should be a no-op now that the schema has the
        # UNIQUE INDEX, but kept for self-healing if it's ever dropped.
        by_source: dict[str, dict[str, Any]] = {}
        dup_cleanup_count = 0
        for source, rows in by_source_lists.items():
            by_source[source] = rows[0]
            for stale in rows[1:]:
                await call_tool(session, "memory_delete", {"id": stale["id"]})
                dup_cleanup_count += 1
        if dup_cleanup_count:
            log.warning("cleaned up %d duplicate rows during snapshot", dup_cleanup_count)
        log.info("found %d existing vault chunks in agent_memory", len(by_source))

        # 2. Walk disk, build set of desired sources.
        desired: set[str] = set()
        upsert_count = 0
        skip_count = 0
        for path in iter_notes(vault_root):
            rel = str(path.relative_to(vault_root))
            try:
                raw = path.read_text(encoding="utf-8")
            except OSError as e:
                log.warning("skipping %s: %s", rel, e)
                continue
            chunks = chunk_markdown(raw)
            top_folder = path.relative_to(vault_root).parts[0] if path.relative_to(vault_root).parts else ""
            for slug, content in chunks:
                source = f"vault:{rel}#{slug}"
                desired.add(source)
                sha = sha256_text(content)
                row = by_source.get(source)
                if row and (row.get("metadata") or {}).get("sha256") == sha:
                    skip_count += 1
                    continue
                # Changed (or new): delete old then insert fresh. The MCP
                # doesn't have an upsert; delete-insert is idempotent enough
                # at hourly cadence.
                if row:
                    await call_tool(session, "memory_delete", {"id": row["id"]})
                tags = ["vault"]
                if top_folder:
                    tags.append(top_folder)
                metadata = {"sha256": sha, "path": rel, "heading": slug}
                await call_tool(session, "memory_insert", {
                    "content": content,
                    "project": "vault",
                    "source": source,
                    "tags": tags,
                    "metadata": metadata,
                })
                upsert_count += 1

        # 3. Delete orphans (rows that no longer have a matching on-disk source).
        orphans = [row for src, row in by_source.items() if src not in desired]
        for row in orphans:
            await call_tool(session, "memory_delete", {"id": row["id"]})

        log.info(
            "vault reconcile complete: %d upserts, %d unchanged, %d orphans removed",
            upsert_count, skip_count, len(orphans),
        )


def main() -> None:
    if "--version" in sys.argv[1:]:
        print(f"vault-indexer {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("VAULT_INDEXER_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    vault_root = Path(os.environ["VAULT_INDEXER_VAULT"]).resolve()
    am_url = os.environ["VAULT_INDEXER_AGENT_MEMORY_URL"].rstrip("/")
    token_file = os.environ["VAULT_INDEXER_TOKEN_FILE"]
    if not vault_root.is_dir():
        raise SystemExit(f"vault root not a directory: {vault_root}")
    with open(token_file) as f:
        bearer = f.read().strip()
    log.info("vault-indexer version %s starting (vault=%s am=%s)", __version__, vault_root, am_url)
    asyncio.run(reconcile(vault_root, am_url, bearer))


if __name__ == "__main__":
    sys.exit(main())
