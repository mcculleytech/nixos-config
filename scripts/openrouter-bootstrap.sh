#!/usr/bin/env bash
# OpenRouter policy CLI — programmatic control of sub-keys via your
# provisioning ("management") key. The provisioning key is read from the
# OPENROUTER_PROVISIONING_KEY env var on every invocation and is NEVER
# persisted to disk by this script.
#
# Commands:
#   bootstrap [name] [limit_usd]   Idempotent: create the Hermes sub-key if
#                                  one with that name doesn't already exist.
#                                  Defaults: name=hermes, limit_usd=20.
#   list                           List all sub-keys with usage + caps.
#   get <hash>                     Inspect one sub-key.
#   update <hash> <field=value>... Update a sub-key (name, disabled,
#                                  include_byok_in_limit, limit_reset).
#   disable <hash>                 Shortcut for: update <hash> disabled=true.
#   enable <hash>                  Shortcut for: update <hash> disabled=false.
#   delete <hash>                  Revoke a sub-key permanently.
#   policy-checklist               Print the UI-only steps (BYOK Gemini
#                                  registration, account-wide privacy
#                                  defaults) the API can't perform.
#
# Recommended invocation pattern — keeps the key out of shell history:
#   read -rs OPENROUTER_PROVISIONING_KEY; export OPENROUTER_PROVISIONING_KEY
#   ./scripts/openrouter-bootstrap.sh bootstrap
#   ./scripts/openrouter-bootstrap.sh list
#   unset OPENROUTER_PROVISIONING_KEY
#
# Bootstrap previously read the key from stdin. That's still supported for
# the `bootstrap` subcommand only — if the env var is unset, the script will
# prompt with a hidden read.

set -euo pipefail

OR_API="${OR_API:-https://openrouter.ai/api/v1}"

# ── Dependencies ────────────────────────────────────────────────────────────
for cmd in curl jq; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    echo "Try: nix shell nixpkgs#$cmd" >&2
    exit 1
  fi
done

# ── Provisioning key handling ───────────────────────────────────────────────
require_key() {
  if [[ -z "${OPENROUTER_PROVISIONING_KEY:-}" ]]; then
    if [[ -t 0 ]]; then
      printf 'OpenRouter provisioning key (input hidden): ' >&2
      IFS= read -rs OPENROUTER_PROVISIONING_KEY
      printf '\n' >&2
    else
      IFS= read -r OPENROUTER_PROVISIONING_KEY
    fi
  fi
  if [[ -z "${OPENROUTER_PROVISIONING_KEY:-}" ]]; then
    echo "No provisioning key supplied. Set OPENROUTER_PROVISIONING_KEY or pipe via stdin." >&2
    exit 1
  fi
}

# ── Auth-wrapped HTTP helpers ───────────────────────────────────────────────
or_get() {
  curl -sS -X GET "$OR_API$1" \
    -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY"
}

or_post() {
  curl -sS -X POST "$OR_API$1" \
    -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" \
    -H "Content-Type: application/json" \
    --data-raw "$2"
}

or_patch() {
  curl -sS -X PATCH "$OR_API$1" \
    -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY" \
    -H "Content-Type: application/json" \
    --data-raw "$2"
}

or_delete() {
  curl -sS -X DELETE "$OR_API$1" \
    -H "Authorization: Bearer $OPENROUTER_PROVISIONING_KEY"
}

die() {
  echo "$1" >&2
  exit 1
}

# ── Commands ────────────────────────────────────────────────────────────────

cmd_list() {
  require_key
  or_get /keys | jq '
    .data
    | map({
        name,
        hash,
        disabled,
        limit,
        limit_reset,
        limit_remaining,
        usage_monthly,
        include_byok_in_limit,
        created_at
      })
  '
}

cmd_get() {
  local hash="${1:?Usage: get <hash>}"
  require_key
  or_get "/keys/$hash" | jq '.'
}

cmd_update() {
  local hash="${1:?Usage: update <hash> <field=value>...}"
  shift
  [[ $# -gt 0 ]] || die "Need at least one field=value pair."

  local body
  body="$(jq -n '{}')"
  for pair in "$@"; do
    local field value
    field="${pair%%=*}"
    value="${pair#*=}"
    case "$field" in
      disabled|include_byok_in_limit)
        body="$(jq --arg f "$field" --argjson v "$value" '. + {($f): $v}' <<<"$body")"
        ;;
      limit)
        body="$(jq --arg f "$field" --argjson v "$value" '. + {($f): $v}' <<<"$body")"
        ;;
      name|limit_reset)
        body="$(jq --arg f "$field" --arg v "$value" '. + {($f): $v}' <<<"$body")"
        ;;
      *)
        die "Unknown field: $field"
        ;;
    esac
  done

  require_key
  or_patch "/keys/$hash" "$body" | jq '.'
}

cmd_disable() {
  local hash="${1:?Usage: disable <hash>}"
  cmd_update "$hash" disabled=true
}

cmd_enable() {
  local hash="${1:?Usage: enable <hash>}"
  cmd_update "$hash" disabled=false
}

cmd_delete() {
  local hash="${1:?Usage: delete <hash>}"
  require_key
  printf 'Revoke sub-key %s? [yes/N] ' "$hash" >&2
  local confirm
  read -r confirm
  [[ "$confirm" == "yes" ]] || die "Aborted."
  or_delete "/keys/$hash" | jq '.'
}

cmd_bootstrap() {
  local name="${1:-hermes}"
  local limit_usd="${2:-20}"
  local limit_reset="${LIMIT_RESET:-monthly}"
  require_key

  # Idempotency: refuse to create a duplicate.
  local existing
  existing="$(or_get /keys | jq -r --arg n "$name" '.data[] | select(.name == $n) | .hash' | head -1)"
  if [[ -n "$existing" ]]; then
    echo "A sub-key named '$name' already exists (hash: $existing)." >&2
    echo "Inspect with: ./scripts/openrouter-bootstrap.sh get $existing" >&2
    echo "Revoke with:  ./scripts/openrouter-bootstrap.sh delete $existing" >&2
    exit 2
  fi

  echo "Creating runtime sub-key '$name' with \$${limit_usd}/${limit_reset} cap..." >&2

  local req
  req="$(jq -n \
    --arg name "$name" \
    --argjson limit "$limit_usd" \
    --arg reset "$limit_reset" \
    '{name: $name, limit: $limit, limit_reset: $reset, include_byok_in_limit: false}')"

  local resp
  resp="$(or_post /keys "$req")"

  local runtime_key key_hash
  runtime_key="$(jq -r '.key // empty' <<<"$resp")"
  key_hash="$(jq -r '.data.hash // empty' <<<"$resp")"

  if [[ -z "$runtime_key" ]]; then
    echo "Key creation failed. Response:" >&2
    jq <<<"$resp" >&2 || echo "$resp" >&2
    exit 1
  fi

  cat >&2 <<EOF

────────────────────────────────────────────────────────────────────────
Runtime sub-key created.
  name:        $name
  hash:        $key_hash
  monthly cap: \$${limit_usd} (resets ${limit_reset}, BYOK excluded)

Next steps (UI-only — see also: $0 policy-checklist):
  1. Register your Gemini key as BYOK so tier-1 traffic bills against the
     Google quota instead of OR credits:
         https://openrouter.ai/settings/integrations
     → "Google AI Studio" → paste your GEMINI_API_KEY.
  2. (Optional) Flip account-wide privacy defaults:
         https://openrouter.ai/settings/privacy
     → "Default to providers that do not log/train".
  3. Paste the runtime key below into sops:
         sops secrets/main.yaml
         # add: openrouter_api_key: <key>
  4. Deploy:
         colmena apply switch --on saruman --impure
────────────────────────────────────────────────────────────────────────
EOF

  # Key to stdout so it can be piped to a clipboard tool.
  printf '%s\n' "$runtime_key"
}

cmd_policy_checklist() {
  cat <<'EOF'
OpenRouter policy items — what the management API can vs. can't do.

API-doable (this script handles):
  ✓ Create sub-keys with monthly credit caps              → bootstrap
  ✓ List sub-keys + usage                                 → list
  ✓ Inspect / rotate / disable / delete sub-keys          → get/update/disable/delete

UI-only (you click through these once on https://openrouter.ai):

  1. BYOK Gemini registration
     URL:    https://openrouter.ai/settings/integrations
     Action: Click "Google AI Studio" → paste GEMINI_API_KEY
     Why:    All `google/gemini-*` model calls then bill the actual
             inference against your Google quota; OR only collects its
             ~5% markup in OR credits.

  2. Account-wide privacy defaults
     URL:    https://openrouter.ai/settings/privacy
     Action: LEAVE the "Do not log or train on my prompts by default"
             toggle OFF for this Hermes account.
     Why:    The tier-1 (Gemini) and tier-3 (Anthropic Sonnet/Opus)
             paths route through providers that OR does not classify as
             ZDR — flipping the account-wide default ON makes every
             tier-1/tier-3 call fail with HTTP 404 ("No endpoints
             available matching your data policy"). Per-request
             `data_collection: deny` on `delegation` + `fallback_model`
             already pins the only paths that need ZDR (the DeepSeek
             calls). The account-wide toggle is the wrong tool here.

  3. (Optional) Spend alert threshold
     URL:    https://openrouter.ai/settings/credits
     Action: Set a low-water-mark email alert (e.g., $5 remaining)
     Why:    The sub-key caps spend hard, but an alert is your first
             signal that something's burning credits faster than expected.

  4. (Optional) Workspace BYOK key priority
     URL:    https://openrouter.ai/workspaces/default/byok
     Action: Drag-order BYOK keys if you register more than one per
             provider. Hermes uses the first matching key.
EOF
}

# ── Dispatch ────────────────────────────────────────────────────────────────
sub="${1:-bootstrap}"
shift || true

case "$sub" in
  bootstrap)         cmd_bootstrap "$@"         ;;
  list)              cmd_list "$@"              ;;
  get)               cmd_get "$@"               ;;
  update)            cmd_update "$@"            ;;
  disable)           cmd_disable "$@"           ;;
  enable)            cmd_enable "$@"            ;;
  delete)            cmd_delete "$@"            ;;
  policy-checklist)  cmd_policy_checklist "$@"  ;;
  -h|--help|help)
    grep -E '^#( |$)' "$0" | sed 's/^# \{0,1\}//'
    ;;
  *)
    echo "Unknown command: $sub" >&2
    echo "Try: $0 help" >&2
    exit 1
    ;;
esac
