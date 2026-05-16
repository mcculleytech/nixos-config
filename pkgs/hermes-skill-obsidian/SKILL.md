---
name: obsidian-vault-policy
description: |
  Hermes-agent's rules of engagement for alex's Obsidian vault. Load this
  whenever the user mentions Obsidian, the vault, notes, daily notes, or
  asks to read/search/write notes. Covers keyword search via vault-mcp
  vs. semantic search via agent-memory (pgvector under project=vault),
  mandates user approval before any vault write, and prefers the MCP
  tools over filesystem operations.
tags:
  - obsidian
  - vault
  - notes
  - mcp-vault
  - alex-policy
date_created: 2026-05-12T17:00:00Z
date_modified: 2026-05-14T18:00:00Z
---

# Obsidian Vault Policy (alex)

Use this skill whenever the conversation references alex's Obsidian
vault: reading notes, searching, daily notes, creating notes,
modifying frontmatter, vault structure questions.

## Tooling preference

**Prefer `mcp_vault_*` over filesystem tools** for vault interaction.
The vault MCP exposes structured access (frontmatter, links, tags) that
plain `read_file` / `search_files` calls don't surface.

| Operation | Use | Avoid |
|---|---|---|
| Read a note | `mcp_vault_vault_read` | `read_file` |
| Keyword search | `mcp_vault_vault_search` | `search_files` |
| Semantic search | `mcp_agent_memory_memory_search` (project=`vault`) | grep / keyword search alone |
| Frontmatter query | `mcp_vault_vault_query_frontmatter` | grep |
| Append to note | `mcp_vault_vault_append` (with approval) | `write_file` |
| Create note | `mcp_vault_vault_create` (with approval) | `write_file` |
| Delete note | `mcp_vault_vault_delete` (with approval) | `rm` / `unlink` |

`read_file` is acceptable as a fallback when the MCP is unreachable or
when the path is outside the vault root.

## Keyword vs. semantic search — pick the right one

The vault is searchable two ways. They're complementary, not redundant:

- **`mcp_vault_vault_search`** — keyword/substring grep against the
  current file contents. Fast (~50ms), exact. Use when the user gave a
  literal term, a name, a phone number, a code symbol, or any string
  that should appear verbatim in the note.

- **`mcp_agent_memory_memory_search`** with `project="vault"` —
  semantic similarity over the pgvector-indexed chunks. The
  `vault-indexer` walks every `*.md` under the vault, splits by
  headings, embeds each chunk, and inserts under
  `source: vault:<relative-path>#<heading-anchor>` so the result path
  is recoverable. Use when the user asks *about a concept*: "notes
  about agent reliability", "things I've written on burnout",
  "what have I jotted down about deploys lately". The query and the
  note don't need to share wording.

Sequence both when uncertain: try keyword first (cheap, narrow), fall
back to semantic if it returns nothing useful. Or run them in
parallel and dedupe by path. **Do not** assume a keyword miss means
the note doesn't exist — paraphrased material is exactly what
semantic catches.

Index freshness: `vault-indexer` reconciles on its own schedule, so
very recently created notes may not yet be in pgvector. If a fresh
note matters for a query, fall back to `mcp_vault_vault_search`.

## Write approval

**NEVER** add new notes, append to notes, or delete notes without
explicit user approval. This applies to every write tool above.

Phrasing for approval requests:

> "I can save this as a new note at `<path>` with title `<title>`. Want
> me to create it?"

> "I can append the following to `<note>`. Approve?"

Only proceed after an unambiguous "yes" / "go ahead" / "do it". Vague
acknowledgements ("ok", "sure" in a different context) don't count.

## Vault structure

Root: `/home/alex/obsidian/Barrow-Downs` (also reachable via
`OBSIDIAN_VAULT_PATH` env var when set).

Daily notes live under `05 - personal notes/YYYY/MM/<MMM-Dth-YYYY>.md`.
Templates live under `98 - templates/`. The `/today` slash command
creates today's daily note from `98 - templates/daily note - template.md`.

## Pitfalls

- **Accidental writes** are the worst failure mode. When in doubt,
  surface the proposed action and stop.
- **Search ambiguity**: when `mcp_vault_vault_search` returns multiple
  matches, cite paths and ask which one the user means rather than
  guessing.
- **Vault root drift**: don't assume the upstream `obsidian` skill's
  default (`~/Documents/Obsidian Vault`) — it doesn't apply here.
