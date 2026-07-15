#!/usr/bin/env bash
set -euo pipefail

REPO="/home/alex/Repositories/nixos-config"
NTFY_TOPIC="deploy"
LOG_TAG="auto-deploy"
GOOD_TAG="deploy/last-known-good"
# Hosts deployed manually (laptops etc.) whose closures we prebuild after a
# successful fleet deploy, so the eventual `colmena apply --on <host>` skips
# straight to copy + activate.
PREBUILD_HOSTS="aeneas"
PREBUILD_ROOT="/home/alex/.local/state/auto-deploy"

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
    # Send git's own chatter ("Switched to...", "Your branch is up to date...")
    # to the log, not stdout — this function's stdout is captured into $ROLLED
    # and interpolated into the failure notification, so it must be the short
    # rev and nothing else.
    git checkout "$rollback_rev" 2>&1 | logger -t "$LOG_TAG" || true
    colmena apply --on "$targets" 2>&1 | logger -t "$LOG_TAG" || true
    git checkout master 2>&1 | logger -t "$LOG_TAG" || true
    echo "$rollback_short"
  else
    echo ""
  fi
}

# Helper: did $host actually activate the config we just built? Compares the
# host's running system to the toplevel we build here — a version-independent
# proof the switch took effect. Replaces the old `grep "Activation successful"`
# guard, which silently broke when a colmena bump changed its log output and
# caused false-failure rollbacks of healthy deploys. $2 = host IP, or "" for
# the local host (saruman).
host_activated() {
  local host="$1" ip="$2" target running
  target=$(nix build --no-link --print-out-paths \
    ".#nixosConfigurations.${host}.config.system.build.toplevel" 2>/dev/null) || return 1
  [ -z "$target" ] && return 1
  if [ -z "$ip" ]; then
    running=$(readlink -f /run/current-system 2>/dev/null)
  else
    running=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "root@${ip}" 'readlink -f /run/current-system' 2>/dev/null)
  fi
  [ -n "$running" ] && [ "$running" = "$target" ]
}

# 1. Pull latest — exit if nothing new since last successful deploy
git fetch origin
git checkout master
git pull --ff-only

LAST_GOOD=$(git rev-parse "$GOOD_TAG" 2>/dev/null || echo "")
CURRENT=$(git rev-parse HEAD)
if [ "$LAST_GOOD" = "$CURRENT" ]; then
  logger -t "$LOG_TAG" "No new commits since last deploy, skipping"
  exit 0
fi

# Bail early if the working tree is dirty — colmena fails with a
# cryptic "cannot update unlocked flake input" error in pure mode.
# Only check tracked files; untracked files don't affect the flake eval.
if [ -n "$(git diff HEAD)" ]; then
  DIRTY_FILES=$(git diff HEAD --name-only | head -10)
  logger -t "$LOG_TAG" "Dirty working tree detected, aborting deploy"
  curl -s -H "Title: Deploy SKIPPED — dirty tree" -H "Priority: default" \
    -d "Uncommitted changes in $(pwd) are blocking colmena (pure eval mode). Files: ${DIRTY_FILES}" \
    "$NTFY_URL" || true
  exit 1
fi

SHORT_REV=$(git rev-parse --short HEAD)
COMMIT_MSG=$(git log -1 --pretty=%s)
logger -t "$LOG_TAG" "New commit detected: $SHORT_REV — $COMMIT_MSG"

# 2. Deploy VMs first (canaries)
#
# colmena exits non-zero (commonly 4) when a unit is failed at the activation
# *snapshot* — including the benign root dbus-broker user-unit reload — even
# when every node activated cleanly. Don't roll back on the exit code alone
# (the saruman step has the same guard): capture it, and only hard-fail if a
# host's running system != the toplevel we built (host_activated) — i.e. the
# switch never took effect (an eval/build error). Otherwise defer to the per-VM
# `systemctl --failed` health check in step 3, the real arbiter for live units.
VM_LOG=$(mktemp)
set +e
colmena apply --on @vm 2>&1 | tee "$VM_LOG" | logger -t "$LOG_TAG"
VM_RC=${PIPESTATUS[0]}
set -e
VM_BAD=""
if [ "$VM_RC" -ne 0 ]; then
  for h in vader phantom atreides; do
    HIP=$(nix eval --raw ".#nixosConfigurations.$h.config.lab.hosts.$h.ip" 2>/dev/null || echo "")
    [ -z "$HIP" ] && continue
    host_activated "$h" "$HIP" || VM_BAD="${VM_BAD} $h"
  done
fi
if [ "$VM_RC" -ne 0 ] && [ -n "$VM_BAD" ]; then
  rm -f "$VM_LOG"
  logger -t "$LOG_TAG" "VM deploy FAILED: activation did not complete on:${VM_BAD} (colmena rc=$VM_RC)"
  ROLLED=$(rollback "@vm")
  if [ -n "$ROLLED" ]; then
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "VM deploy failed at $SHORT_REV ($COMMIT_MSG): activation did not complete (rc=$VM_RC). Rolled back to $ROLLED." "$NTFY_URL" || true
  else
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "VM deploy failed at $SHORT_REV ($COMMIT_MSG): activation did not complete (rc=$VM_RC). No known-good revision to roll back to." "$NTFY_URL" || true
  fi
  exit 1
fi
rm -f "$VM_LOG"
if [ "$VM_RC" -ne 0 ]; then
  logger -t "$LOG_TAG" "colmena rc=$VM_RC on @vm but activation completed — deferring to health check"
  # Let Restart= settle any transient activation-snapshot failures before the
  # health check renders a verdict.
  sleep 20
else
  logger -t "$LOG_TAG" "VM deploy succeeded"
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
#
# colmena exits non-zero (commonly 4) when ANY unit is failed at the
# activation *snapshot* — even one that systemd's Restart= heals seconds
# later. saruman runs the MCP/hermes cluster, which briefly fails on a deploy
# that also restarts tailscaled (see mcp/default.nix), so the bare exit code
# is a false negative. Judge saruman on the SETTLED state instead: capture the
# real exit code, and if it's non-zero, distinguish a genuine failure
# (activation never completed) from a transient flap (activation completed,
# units heal) by checking the running system equals the built toplevel
# (host_activated) and then re-running a `systemctl --failed` check after a grace period.
SARUMAN_LOG=$(mktemp)
set +e
colmena apply --on saruman 2>&1 | tee "$SARUMAN_LOG" | logger -t "$LOG_TAG"
SARUMAN_RC=${PIPESTATUS[0]}
set -e

SARUMAN_OK=1
SARUMAN_REASON=""
if [ "$SARUMAN_RC" -ne 0 ]; then
  if ! host_activated saruman ""; then
    SARUMAN_OK=0
    SARUMAN_REASON="activation did not complete (colmena rc=$SARUMAN_RC)"
  else
    logger -t "$LOG_TAG" "colmena rc=$SARUMAN_RC but activation completed — settling 30s before health check"
    sleep 30
    FAILED_UNITS=$(systemctl --failed --no-legend | grep -v 'auto-deploy.service' || true)
    if [ -n "$FAILED_UNITS" ]; then
      SARUMAN_OK=0
      SARUMAN_REASON="units still failed after settle: $(echo "$FAILED_UNITS" | grep -oE '[^[:space:]]+\.(service|socket|timer|target|mount|path)' | tr '\n' ' ')"
    fi
  fi
fi
rm -f "$SARUMAN_LOG"

if [ "$SARUMAN_OK" = "1" ]; then
  logger -t "$LOG_TAG" "Saruman deploy succeeded (colmena rc=$SARUMAN_RC)"
else
  logger -t "$LOG_TAG" "Saruman deploy FAILED: $SARUMAN_REASON"
  ROLLED=$(rollback "saruman")
  if [ -n "$ROLLED" ]; then
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Saruman deploy failed at $SHORT_REV ($SARUMAN_REASON): $COMMIT_MSG. Rolled back to $ROLLED." "$NTFY_URL" || true
  else
    curl -s -H "Title: Deploy FAILED" -H "Priority: high" -d "Saruman deploy failed at $SHORT_REV ($SARUMAN_REASON): $COMMIT_MSG. No known-good revision to roll back to." "$NTFY_URL" || true
  fi
  exit 1
fi

# 5. Tag as last-known-good and notify
git tag -f "$GOOD_TAG" HEAD
git push -f origin "$GOOD_TAG" 2>&1 | logger -t "$LOG_TAG" || true

# 6. Check if VMs need a reboot (kernel changed)
REBOOT_HOSTS=""
for host in vader phantom atreides; do
  IP=$(nix eval --raw ".#nixosConfigurations.$host.config.lab.hosts.$host.ip" 2>/dev/null || echo "")
  if [ -z "$IP" ]; then continue; fi
  NEEDS_REBOOT=$(ssh -o ConnectTimeout=10 -o BatchMode=yes "root@$IP" \
    'booted=$(readlink /run/booted-system/kernel); current=$(readlink /run/current-system/kernel); [ "$booted" != "$current" ] && echo "yes" || echo "no"' 2>/dev/null || echo "no")
  if [ "$NEEDS_REBOOT" = "yes" ]; then
    logger -t "$LOG_TAG" "Kernel changed on $host — scheduling reboot"
    ssh -o ConnectTimeout=10 -o BatchMode=yes "root@$IP" 'shutdown -r +1 "Kernel update — auto-reboot"' 2>/dev/null || true
    REBOOT_HOSTS="${REBOOT_HOSTS} ${host}"
  fi
done

# 6b. Check if saruman itself needs a reboot (can't self-reboot)
BOOTED=$(readlink /run/booted-system/kernel)
CURRENT=$(readlink /run/current-system/kernel)
if [ "$BOOTED" != "$CURRENT" ]; then
  logger -t "$LOG_TAG" "Kernel changed on saruman — manual reboot required"
  curl -s -H "Title: Saruman needs reboot" -H "Priority: high" -d "$SHORT_REV updated the kernel on saruman. Manual reboot required." "$NTFY_URL" || true
fi

logger -t "$LOG_TAG" "Deploy complete: $SHORT_REV (tagged $GOOD_TAG)"

# 7. Wait for rebooted hosts to come back, then send success notification
if [ -n "$REBOOT_HOSTS" ]; then
  logger -t "$LOG_TAG" "Waiting for rebooted hosts to come back..."
  sleep 120  # wait for reboot (1 min shutdown delay + boot time)
  BACK=""
  DOWN=""
  for host in $REBOOT_HOSTS; do
    IP=$(nix eval --raw ".#nixosConfigurations.$host.config.lab.hosts.$host.ip" 2>/dev/null || echo "")
    if [ -z "$IP" ]; then continue; fi
    # retry a few times — host may still be booting
    ALIVE=0
    for attempt in 1 2 3; do
      if ssh -o ConnectTimeout=15 -o BatchMode=yes "root@$IP" 'systemctl --failed --no-legend' 2>/dev/null; then
        ALIVE=1
        break
      fi
      sleep 30
    done
    if [ "$ALIVE" = "1" ]; then
      BACK="${BACK} ${host}"
      logger -t "$LOG_TAG" "Heartbeat OK: $host"
    else
      DOWN="${DOWN} ${host}"
      logger -t "$LOG_TAG" "Heartbeat FAILED: $host did not come back"
    fi
  done

  if [ -n "$DOWN" ]; then
    curl -s -H "Title: REBOOT FAILED" -H "Priority: urgent" -d "Hosts did not come back after reboot:${DOWN}" "$NTFY_URL" || true
  else
    curl -s -H "Title: Deploy SUCCESS" -d "$SHORT_REV — $COMMIT_MSG. Rebooted:${BACK}" "$NTFY_URL" || true
    logger -t "$LOG_TAG" "All hosts back:${BACK}"
  fi
else
  curl -s -H "Title: Deploy SUCCESS" -d "$SHORT_REV — $COMMIT_MSG" "$NTFY_URL" || true
fi

# 8. Prebuild manual-deploy hosts (laptops etc.) so their closures are already
# in saruman's store — the eventual `colmena apply --on <host>` then skips the
# build and goes straight to copy + activate. Runs last so a slow build (flake
# bumps can take an hour) never delays the fleet deploy or health checks.
# --out-link creates a GC root: without one, the daily nix-collect-garbage
# would collect the unrooted closure before it's ever deployed. Each build
# replaces the link, so only the newest prebuilt closure stays rooted.
mkdir -p "$PREBUILD_ROOT"
for host in $PREBUILD_HOSTS; do
  logger -t "$LOG_TAG" "Prebuilding $host toplevel"
  if nix build --out-link "$PREBUILD_ROOT/$host" \
      ".#nixosConfigurations.${host}.config.system.build.toplevel" 2>&1 | logger -t "$LOG_TAG"; then
    logger -t "$LOG_TAG" "Prebuild OK: $host"
  else
    logger -t "$LOG_TAG" "Prebuild FAILED: $host"
    curl -s -H "Title: Prebuild failed" -d "Prebuild of $host failed at $SHORT_REV — next manual deploy will build from scratch." "$NTFY_URL" || true
  fi
done
