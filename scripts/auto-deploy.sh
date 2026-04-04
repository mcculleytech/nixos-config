#!/usr/bin/env bash
set -euo pipefail

REPO="/home/alex/Repositories/nixos-config"
NTFY_TOPIC="deploy"
LOG_TAG="auto-deploy"

cd "$REPO"

# Derive ntfy URL from git-crypt secrets
DOMAIN=$(nix eval --raw '.#nixosConfigurations.atreides.config.services.ntfy-sh.settings.base-url' 2>/dev/null || echo "")
if [ -z "$DOMAIN" ]; then
  DOMAIN="http://localhost:2586"
fi
NTFY_URL="${DOMAIN}/${NTFY_TOPIC}"

# 1. Pull latest — exit if no new commits
git fetch origin master
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
  curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "VM deploy failed at $SHORT_REV: $COMMIT_MSG" "$NTFY_URL" || true
  exit 1
fi

# 3. Health check VMs
FAILED=0
for host in vader phantom atreides; do
  IP=$(nix eval --raw ".#nixosConfigurations.$host.config.lab.hosts.$host.ip" 2>/dev/null || echo "")
  if [ -z "$IP" ]; then continue; fi
  FAILED_UNITS=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "root@$IP" 'systemctl --failed --no-legend' 2>/dev/null || echo "CONNECTION_FAILED")
  if [ -z "$FAILED_UNITS" ]; then
    logger -t "$LOG_TAG" "Health check PASSED: $host"
  else
    logger -t "$LOG_TAG" "Health check FAILED: $host — $FAILED_UNITS"
    FAILED=1
  fi
done

if [ "$FAILED" = "1" ]; then
  curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Health check failed on VMs at $SHORT_REV" "$NTFY_URL" || true
  exit 1
fi

# 4. Deploy saruman (self)
if colmena apply --on saruman 2>&1 | logger -t "$LOG_TAG"; then
  logger -t "$LOG_TAG" "Saruman deploy succeeded"
else
  curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Saruman deploy failed at $SHORT_REV: $COMMIT_MSG" "$NTFY_URL" || true
  exit 1
fi

# 5. Success notification
curl -s -H "Title: Deploy SUCCESS" -d "$SHORT_REV — $COMMIT_MSG" "$NTFY_URL" || true
logger -t "$LOG_TAG" "Deploy complete: $SHORT_REV"
