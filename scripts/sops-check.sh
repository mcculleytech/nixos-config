#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ./scripts/check-sops-host-key.sh --host <hostname> [--ssh root@ip] [--role server|workstation] [--apply]

What it does:
  1. Reads remote /etc/ssh/ssh_host_ed25519_key.pub
  2. Converts it to age recipient with ssh-to-age
  3. Verifies recipient is present in .sops.yaml keys
  4. Verifies creation_rules reference expected anchor (*<host>_<role>)
  5. Checks whether secrets already include that recipient
  6. Optionally runs sops updatekeys -y on files that need it (--apply)

Examples:
  ./scripts/check-sops-host-key.sh --host saruman --ssh root@10.1.8.50
  ./scripts/check-sops-host-key.sh --host saruman --ssh root@10.1.8.50 --apply
EOF
}

HOST=""
SSH_TARGET=""
ROLE="server"
APPLY=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)
      HOST="${2:-}"
      shift 2
      ;;
    --ssh)
      SSH_TARGET="${2:-}"
      shift 2
      ;;
    --role)
      ROLE="${2:-}"
      shift 2
      ;;
    --apply)
      APPLY=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

if [[ -z "$HOST" ]]; then
  echo "--host is required" >&2
  usage
  exit 1
fi

ROOT_DIR="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
cd "$ROOT_DIR"

SOPS_CFG=".sops.yaml"
if [[ ! -f "$SOPS_CFG" ]]; then
  echo "Missing $SOPS_CFG in $ROOT_DIR" >&2
  exit 1
fi

for cmd in ssh ssh-to-age sops rg find sed sort; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    echo "Missing required command: $cmd" >&2
    exit 1
  fi
done

SSH_TARGET="${SSH_TARGET:-root@${HOST}}"
ANCHOR="${HOST//-/_}_${ROLE}"

echo "Target host: $HOST"
echo "SSH target:  $SSH_TARGET"
echo "Anchor name: &$ANCHOR"
echo

echo "Fetching remote host SSH key..."
PUBKEY="$(ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new "$SSH_TARGET" \
  'cat /etc/ssh/ssh_host_ed25519_key.pub')"

RECIPIENT="$(printf '%s\n' "$PUBKEY" | ssh-to-age | tr -d '\r\n')"
if [[ ! "$RECIPIENT" =~ ^age1[0-9a-z]+$ ]]; then
  echo "Could not derive a valid age recipient from remote SSH key." >&2
  exit 1
fi

echo "Computed age recipient:"
echo "  $RECIPIENT"
echo

HAS_RECIPIENT=0
if rg -q --fixed-strings "$RECIPIENT" "$SOPS_CFG"; then
  HAS_RECIPIENT=1
  echo "OK: recipient already present in $SOPS_CFG"
else
  echo "MISSING: recipient not found in $SOPS_CFG"
  echo "Suggested keys entry:"
  echo "  - &$ANCHOR $RECIPIENT"
fi

if rg -q --fixed-strings "*$ANCHOR" "$SOPS_CFG"; then
  echo "OK: creation_rules reference *$ANCHOR"
else
  echo "MISSING: creation_rules do not reference *$ANCHOR"
  echo "Add *$ANCHOR to relevant rule(s) in $SOPS_CFG"
fi

echo
echo "Checking encrypted files for this recipient..."
mapfile -t SECRET_FILES < <(
  {
    [[ -f secrets/main.yaml ]] && printf '%s\n' secrets/main.yaml
    find hosts -maxdepth 2 -type f -name 'secrets.yaml' | sort
  } | sed '/^$/d'
)

if [[ ${#SECRET_FILES[@]} -eq 0 ]]; then
  echo "No secret files found."
  exit 1
fi

MISSING_FILES=()
for file in "${SECRET_FILES[@]}"; do
  if rg -q --fixed-strings "recipient: $RECIPIENT" "$file"; then
    echo "OK: $file"
  else
    echo "NEEDS-UPDATEKEYS: $file"
    MISSING_FILES+=("$file")
  fi
done

echo
if [[ ${#MISSING_FILES[@]} -eq 0 ]]; then
  echo "All checked secret files already include this recipient."
else
  echo "${#MISSING_FILES[@]} file(s) need re-encryption/updatekeys."
fi

if (( APPLY == 1 )); then
  echo
  if (( HAS_RECIPIENT == 0 )); then
    echo "Refusing --apply: recipient is missing from $SOPS_CFG." >&2
    echo "Add it to keys + creation_rules first, then rerun."
    exit 2
  fi

  if [[ ${#MISSING_FILES[@]} -gt 0 ]]; then
    echo "Running sops updatekeys..."
    for file in "${MISSING_FILES[@]}"; do
      echo "  sops updatekeys -y $file"
      sops updatekeys -y "$file"
    done
  else
    echo "--apply requested, but nothing needed updatekeys."
  fi
fi

echo
echo "Recommended deploy pattern:"
echo "  nixos-anywhere --copy-host-keys --flake '.#$HOST' '$SSH_TARGET'"
