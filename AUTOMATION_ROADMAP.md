# Automation Roadmap

Two parallel tracks for automating the homelab — pick one or run both side by side. Both tracks share the same **Phase 0** foundation.

## Phase 0: Shared Foundation (both tracks)

These steps are prerequisites regardless of which track you follow.

**Colmena on Local IPs:**

All servers are on-prem, so there's no reason to route Colmena through Tailscale. Replace hostname-based `targetHost` in `colmena.nix` with static IPs and centralize the IP map in one place (e.g. a shared attrset or `hosts.nix` file) so Colmena, Blocky DNS, and Traefik all reference the same source of truth.

| Host     | Subnet        | Current `targetHost` | New `targetHost`    |
| -------- | ------------- | -------------------- | ------------------- |
| saruman  | `10.1.8.0/24` | `saruman`            | static IP           |
| vader    | `10.2.1.0/24` | `vader`              | static IP           |
| phantom  | `10.1.8.0/24` | `phantom`            | static IP           |
| atreides | `10.1.8.0/24` | `atreides`           | static IP           |

- [x] Switch Colmena `targetHost` values to static IPs
- [ ] Centralize IP mappings in a single `hosts.nix` attrset

**Monitoring Stack (Prometheus + Grafana):**

Shared across both tracks — observability is useful regardless of how deploys happen.

- [x] Deploy Prometheus as a NixOS module (on atreides) ✅ 2026-03-17
- [x] `prometheus-node-exporter` on every host for hardware/OS metrics ✅ 2026-03-17
- [x] Grafana dashboards for system health, disk usage, service status ✅ 2026-03-17
- [ ] Alertmanager rules for disk full, service down, high load — notify via ntfy/email
- [ ] Optional: Loki for centralized log aggregation

**Auto-Update Pipeline:**

The weekly `update-flake.yml` workflow already creates flake.lock update PRs via `DeterminateSystems/update-flake-lock`. The remaining work connects that to a full validate → merge → staged deploy loop.

- [x] **CI validation job:** `nix flake check` workflow on PRs with branch protection ✅ 2026-04-03
- [x] **Auto-merge:** auto-merge flake lock update PRs after CI passes ✅ 2026-04-03
- [ ] **Staged deploy workflow** triggered on merge to `main`:
  - Stage 1: `colmena apply --on @vm` (vader, phantom, atreides)
  - Health check: SSH into each VM, verify systemd units are healthy and critical services respond on expected ports
  - Stage 2: `colmena apply` on physical servers (saruman) — only runs if Stage 1 health checks pass
  - Health check on physical hosts
  - Notify on success/failure via ntfy or webhook
- [ ] **Rollback on failure:** if health checks fail, `nixos-rebuild switch --rollback` on affected hosts and send alert

```
Weekly cron → update-flake.yml → flake.lock PR
  → CI: nix flake check + colmena build → auto-merge if green
  → Deploy Stage 1: colmena apply --on @vm → health check
  → Deploy Stage 2: colmena apply (physical) → health check
  → on failure: rollback + alert
```

---

## Track A: Traditional Ops (zero AI)

A fully deterministic, script-driven pipeline. Every decision is encoded in shell scripts, GitHub Actions workflows, and Nix expressions. No LLMs, no inference, no magic — just well-understood tools.

### A1: Self-Hosted CI/CD Runner

Deploy a GitHub Actions self-hosted runner on **saruman** (Ryzen 5, Nvidia 1080 — already the beefiest box). This keeps builds on LAN with direct SSH access to every host.

- [ ] Add `services.github-runners` NixOS module to saruman's config
- [ ] Generate and sops-encrypt a GitHub runner registration token
- [ ] Create a dedicated SSH deploy key (sops-managed) that the runner uses to reach all hosts
- [ ] Label the runner (e.g. `self-hosted`, `nix`, `homelab`) for workflow targeting

### A2: CI/CD Pipeline

Builds on the shared [Auto-Update Pipeline](#phase-0-shared-foundation-both-tracks) from Phase 0. The staged deploy workflow and auto-merge logic live there — this section covers the additional CI/CD pieces.

- [ ] Cachix binary cache integration to avoid redundant builds across PR checks and deploys
- [ ] Manual workflow dispatch for deploying a single host on demand (`colmena apply --on hostname`)
- [ ] Extend the staged deploy workflow to also support ad-hoc deploys (not just flake.lock updates)

### A3: Proxmox VM Automation

Declaratively manage VM lifecycle so spinning up a new NixOS server is a single PR.

- [ ] Terraform with the `bpg/proxmox` provider — define VMs (CPU, RAM, disk, network) as code
- [ ] Post-provision hook: `nixos-anywhere --copy-host-keys --flake '.#hostname' root@ip`
- [ ] Integrate `sops-check.sh` into the pipeline to auto-enroll new host keys
- [ ] Store Terraform state encrypted in the repo or in a remote backend
- [ ] Alternative: evaluate `nixos-generators` for building Proxmox-ready images directly from flake

### A4: Health Checks and Rollback

- [ ] CI step after `colmena apply`: SSH into each host, verify systemd units are healthy
- [ ] Check critical services (Traefik, Blocky, Jellyfin, etc.) respond on expected ports
- [ ] On failure: `colmena apply --on @failed-host` with previous known-good revision, or `nixos-rebuild switch --rollback`
- [ ] CI tags each successful deploy commit so there's always a known-good ref to roll back to

### A5: Full GitOps Loop

Close the loop — the repo becomes the single source of truth with zero manual intervention. The auto-update pipeline (Phase 0) handles flake.lock PRs, CI validation, auto-merge, and staged deploys. This section covers the remaining GitOps pieces.

- [x] Branch protection on `main`: require CI checks before merge ✅ 2026-04-03
- [ ] Scheduled drift detection: nightly `colmena apply --evaluator streaming --verbose --what-if` dry-run, alert if actual state diverges from repo
- [ ] Self-healing: if drift is detected, auto-apply to bring hosts back in line (optional, aggressive)

### Track A End State

```
git push → GitHub Actions (saruman runner) → nix flake check → cachix push
  → colmena apply → health checks → notify
  → on failure: auto-rollback + alert

Weekly: flake.lock update PR → auto-merge if green → full deploy cycle

New VM: Terraform apply → nixos-anywhere bootstrap → sops enroll → colmena apply
```

---

## Track B: AI-Augmented Ops

Layer AI into the operations workflow. The underlying infrastructure (Colmena, Prometheus, NixOS) stays the same — AI acts as an intelligent operator on top of it, handling triage, analysis, and generation of changes that still go through normal review.

### B1: AI-Assisted Config Generation

Use an LLM to generate NixOS module configs from natural language descriptions, reducing boilerplate and speeding up new service onboarding.

- [ ] Local LLM on **saruman** (Ollama + CodeLlama/Deepseek-Coder or similar) — keep everything on-prem, no API keys
- [ ] Prompt templates for common tasks: "add a new NixOS service", "create a Colmena node", "write a disko config for X"
- [ ] CLI wrapper script: `./ai-gen service --name foo --port 8080` → generates a module scaffold
- [ ] All AI output lands in a feature branch for human review — never auto-merged

### B2: Intelligent Alerting and Triage

Replace static Alertmanager rules with an AI layer that correlates metrics and provides actionable context when things break.

- [ ] Feed Prometheus alerts + recent metrics into a local LLM for root-cause analysis
- [ ] Alert enrichment: when Alertmanager fires, an AI summary is appended to the ntfy/Slack notification with probable cause and suggested remediation
- [ ] Runbook generation: AI produces step-by-step remediation based on the alert type and host context
- [ ] Correlation: group related alerts (e.g. high load + OOM + service restart) into a single incident summary

### B3: Log Analysis with AI

Use AI to surface anomalies and patterns in logs that static rules would miss.

- [ ] Loki for centralized log aggregation (shared with Track A if both run)
- [ ] Periodic log summarization: cron job feeds recent logs to LLM, outputs a daily digest of notable events
- [ ] Anomaly detection: flag log patterns that deviate from baseline (e.g. sudden spike in auth failures, unusual systemd restarts)
- [ ] Query interface: natural language queries against logs — "what happened on phantom between 2am and 4am?"

### B4: AI-Assisted PR Review and Drift Remediation

Use AI to review incoming Nix changes and auto-generate fixes for config drift.

- [ ] PR review bot: on new PR, LLM analyzes the Nix diff for common mistakes (missing `mkEnableOption`, wrong option types, security issues like open ports)
- [ ] Drift remediation: when scheduled drift detection (from Phase 0) finds divergence, AI generates a PR with the fix instead of just alerting
- [ ] Dependency analysis: when `flake.lock` updates, AI summarizes what changed upstream and flags breaking changes before the auto-update pipeline (Phase 0) auto-merges
- [ ] Nix evaluation error helper: on CI failure, AI reads the eval error and suggests a fix in a PR comment

### B5: Conversational Homelab Management

A chat interface for managing the homelab through natural language.

- [ ] Local chatbot (Ollama-backed) with access to the repo, Prometheus API, and Colmena
- [ ] Commands like: "deploy the latest config to all VMs", "show me saruman's CPU usage this week", "what services are running on atreides?"
- [ ] Safety rails: destructive actions (deploy, rollback, VM delete) require explicit confirmation
- [ ] Context-aware: bot knows the repo structure, host inventory, and current Prometheus state

### Track B End State

```
Alert fires → Prometheus → Alertmanager → AI triage (local LLM)
  → enriched notification with root cause + suggested fix
  → if auto-remediable: AI opens a PR → human approves → colmena apply

New service request → natural language → AI generates Nix module
  → PR opened → AI + human review → merge → deploy

Daily: AI log digest → anomaly report → flag issues before they alert

Drift detected → AI generates remediation PR → auto-deploy if approved
```
