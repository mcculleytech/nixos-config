#!/usr/bin/env bash
set -euo pipefail

REPO="/home/alex/Repositories/nixos-config"
NTFY_TOPIC="deploy"
LOG_TAG="auto-deploy"
GOOD_TAG="deploy/last-known-good"

cd "$REPO"

# Derive ntfy URL from git-crypt secrets
DOMAIN=$(nix eval --raw '.#nixosConfigurations.atreides.config.services.ntfy-sh.settings.base-url' 2>/dev/null || echo "")
if [ -z "$DOMAIN" ]; then
  DOMAIN="http://localhost:2586"
fi
NTFY_URL="${DOMAIN}/${NTFY_TOPIC}"

# Helper: get last-known-good rev (empty string if tag doesn't exist)
get_rollback_rev() {
  git rev-parse "$GOOD_TAG" 2>/dev/null || echo ""
}

# Helper: rollback a set of hosts to last-known-good
rollback() {
  local targets="$1"
  local rollback_rev
  rollback_rev=$(get_rollback_rev)
  if [ -n "$rollback_rev" ]; then
    local rollback_short
    rollback_short=$(git rev-parse --short "$rollback_rev")
    logger -t "$LOG_TAG" "Rolling back $targets to $rollback_short"
    git checkout "$rollback_rev"
    colmena apply --on "$targets" 2>&1 | logger -t "$LOG_TAG" || true
    git checkout master
    echo "$rollback_short"
  else
    echo ""
  fi
}

# 1. Pull latest — exit if no new commits
git fetch origin
LOCAL=$(git rev-parse master)
REMOTE=$(git rev-parse origin/master)
if [ "$LOCAL" = "$REMOTE" ]; then
  logger -t "$LOG_TAG" "No new commits, skipping deploy"
  exit 0
fi

git checkout master
git pull --ff-only

SHORT_REV=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
logger -t "$LOG_TAG" "New commit detected: $SHORT_REV — $COMMIT_MSG"

# 2. Deploy VMs first (canaries)
if colmena apply --on @vm 2>&1 | logger -t "$LOG_TAG"; then
  logger -t "$LOG_TAG" "VM deploy succeeded"
else
  ROLLED=$(rollback "@vm")
  if [ -n "$ROLLED" ]; then
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "VM deploy failed at $SHORT_REV: $COMMIT_MSG. Rolled back to $ROLLED." "$NTFY_URL" || true
  else
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "VM deploy failed at $SHORT_REV: $COMMIT_MSG. No known-good revision to roll back to." "$NTFY_URL" || true
  fi
  exit 1
fi

# 3. Health check VMs
FAILED=0
FAILED_HOSTS=""
for host in vader phantom atreides; do
  IP=$(nix eval --raw ".#nixosConfigurations.$host.config.lab.hosts.$host.ip" 2>/dev/null || echo "")
  if [ -z "$IP" ]; then continue; fi
  FAILED_UNITS=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "root@$IP" 'systemctl --failed --no-legend' 2>/dev/null || echo "CONNECTION_FAILED")
  if [ -z "$FAILED_UNITS" ]; then
    logger -t "$LOG_TAG" "Health check PASSED: $host"
  else
    logger -t "$LOG_TAG" "Health check FAILED: $host — $FAILED_UNITS"
    FAILED=1
    FAILED_HOSTS="${FAILED_HOSTS} ${host}"
  fi
done

if [ "$FAILED" = "1" ]; then
  ROLLED=$(rollback "@vm")
  if [ -n "$ROLLED" ]; then
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Health check failed on:${FAILED_HOSTS} at $SHORT_REV. Rolled back to $ROLLED." "$NTFY_URL" || true
  else
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Health check failed on:${FAILED_HOSTS} at $SHORT_REV. No known-good revision to roll back to." "$NTFY_URL" || true
  fi
  exit 1
fi

# 4. Deploy saruman (self)
if colmena apply --on saruman 2>&1 | logger -t "$LOG_TAG"; then
  logger -t "$LOG_TAG" "Saruman deploy succeeded"
else
  ROLLED=$(rollback "saruman")
  if [ -n "$ROLLED" ]; then
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Saruman deploy failed at $SHORT_REV: $COMMIT_MSG. Rolled back to $ROLLED." "$NTFY_URL" || true
  else
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Saruman deploy failed at $SHORT_REV: $COMMIT_MSG. No known-good revision to roll back to." "$NTFY_URL" || true
  fi
  exit 1
fi

# 5. Tag as last-known-good and notify
git tag -f "$GOOD_TAG" HEAD
git push -f origin "$GOOD_TAG" 2>&1 | logger -t "$LOG_TAG" || true
curl -s -H "Title: Deploy SUCCESS" -d "$SHORT_REV — $COMMIT_MSG" "$NTFY_URL" || true
logger -t "$LOG_TAG" "Deploy complete: $SHORT_REV (tagged $GOOD_TAG)"
