# Overview
[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

**A Quick Note of Thanks**
This repo was heavily influenced (and parts of it shamelessly taken from) [Misterio77's nix-config](https://github.com/Misterio77/nix-config) repo. Without his work, this repo would not be possible. 

This repository holds my NixOS infrastructure. I don't claim to be a Nix or NixOS expert. I don't work in DevOps and I'm very much still learning this language/package manager/ OS, this is just a hobby of mine that's been a lot of fun to play with.  With that being said, I hope you find something useful while you're here!

_One Config to rule them all, One Config to find them; One Config to bring them all and in the Nix Language bind them._

## Systems

| **Name** | Purpose                  											  							| Hardware                    |
| -------- | ---------------------------------------------------------------------------------------------- | --------------------------- |
| aeneas   | Personal Laptop          											  							| AMD Framework 13in          |
| achilles | Personal Desktop         											  							| AMD Ryzen 5 <br>Nvidia 3050 |
| maul     | Offsite Backup Server    											  							| HP EliteBook 8460p          |
| saruman  | Local AI Server <br> Octoprint Server <br> Jellyfin Server 								  	| AMD Ryzen 5 <br>Nvidia 1080 |
| vader    | Test Machine <br> Xonotic Server									  							| Proxmox VM                  |
| phantom  | Tailscale Subnet Router <br> Syncthing Server <br> Radicale Server <br> Blocky DNS Server  	| Proxmox VM                  |
| atreides | Blocky DNS Server <br> Homepage-dashboard <br> Traefik Reverse Proxy     						| Proxmox VM                  |

## Features

- disk configuration via `disko` with various features including:
	- btrfs subvol setup and encryption (usb and password based encryption)
	- labeling drives
	- blank root subvol snapshotting for `impermanence`
- Tailscale autoenroll & connect
- impermanence with options for ignoring `/home subvol`
- secret management via `sops-nix` & `git-crypt`
- deployable via `nixos-anywhere`
- `syncthing` setup utilizing `git-crypt` for secret management of IDs.

##  ToDo

### Desktop
- [x] Tailscale NFS fix ✅ 2024-10-4
- [ ] Different DEs/TWM setups
	- [ ] Hyprland - WIP
		- [ ] Move manual dotfiles that cannot currently be configured by Home Manager
			- [ ] Hyprlock
			- [ ] Hypridle
			- [ ] kanshi
			- [x] Hyprpaper
	- [x] KDE ✅ 2024-07-12
- [x] install `wakeonlan` ✅ 2024-02-20
- [x] Steam ✅ 2024-07-12
- [ ] Add `mkEnableOption` modularity to desktop/workstation configs (matching server pattern)

### Servers
- [x] Colmena setup
	- [ ] Switch Colmena `targetHost` from Tailscale hostnames to local IPs — all boxes are on-prem, no need for Tailscale
- [x] KVM Server
- [ ] Standalone home manager config for wsl2 or Mac
- [x] Tailscale Subnet Router ✅ 2024-03-10
- [x] Syncthing ✅ 2024-03-10
	- [x] username and password ✅ 2024-03-10
	- [x] standalone server - make syncthing more configurable for all endpoints. ✅ 2024-03-10
- [x] Homelab Dashboard
	- [x] Basic config
	- [x] Configure services
	- [x] Configure Widgets
- [x] Traefik Reverse Proxy ✅ 2024-03-20
	- [x] Let's Encrypt auto cert renewal ✅ 2024-03-20
- [x] Radicale CardDav and CalDav Server ✅ 2024-03-23
- [x] Gitea server fix ✅ 2024-10-04
- [x] Jellyfin in Nix, decom ubuntu docker server ✅ 2024-08-01
- [ ] Arion for docker compose configurations
- [ ] RSS feed server
- [ ] n8n automation platform
- [ ] Prometheus + Grafana monitoring stack
- [x] Fix home-manager impermanence issue where the systemd units aren't mounted for hm.


### Other
- [x] Move all machines to an `impermanence` setup ✅ 2024-03-08
	- [x] Need to redeploy `maul.nix` - Hardware refresh ✅ 2024-03-08
 	- [x] Set as part of global config ✅ 2024-03-08
- [ ] Investigate copy host keys in nixos-anywhere breaking on first deployment run. Might be breaking due to impermanence.
- [x] immutable users as default ✅ 2024-02-20
- [x] Clean up `flake.nix`
- [x] Fix GitHub Action that should autoupdate flake.lock ✅ 2024-08-01
- [ ] Blocky DNS
	- [ ] Multiple Nodes connected via Redis (?)
	- [x] Multiple Servers ✅ 2024-03-20
- [ ] Organize different parts of NixOS & `home-manager` nix configs
	- [x] Role-based directory structure for Desktop and Server (`roles/server/`, `roles/workstation/`) with `mkEnableOption` patterns
	- [ ] Further consolidation (e.g. single function for group-based settings)
- [ ] Dev environment `devShells` off root of project (Go, Python, Rust, C)
- [ ] Full Homelab Automation — Traditional Ops & AI-Augmented Ops (see [Automation Roadmap](#automation-roadmap) below)
- [x] Disko configs for: ✅ 2024-03-01
	- [x] achilles ✅ 2024-02-20
	- [x] aeneas ✅ 2024-02-20
	- [x] server template ✅ 2024-03-01
	- [x] workstation template ✅ 2024-02-20

## Notes

### Deployment Steps
1. Create a `disko` config file for the remote machine
2. Make entries in `flake.nix`, create file `hosts/<hostname>/configuration.nix`
3. copy ssh key to machine
	1. create root login password on remote host
		1. On remote host at login screen switch to root user with `sudo su`
		2. create password with `passwd`
	2. From host machine use `ssh-copy-id root@<ip>` to copy your ssh key for the root user.
4. (optional) Test connection to the box with `ssh root@<ip>`. 
	1. If on physical hardware run `nixos-generate-config --no-filesystems --root /mnt` per `nixos-anywhere` documentation. This allows you to get all the needed hardware specifics. You can also utilize the [nixos-hardware flake](https://github.com/NixOS/nixos-hardware) repository.
5. (optional) If you want encryption on your disk, ensure the `disko` config has been setup for luks. If using an interactive encryption unlock, ensure the file on the remote machine is present. An example of this can be seen in the `dekstop-template.nix` file in this project. 
6. (optional) If using sops nix, you'll need to grab the machine's host key in order for the machine to read secrets. Use the following command on the remote host:
	`nix-shell -p ssh-to-age --run 'cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age'`
7. Run the `nixos-anywhere` installation command:
	I've found that if you need to `--copy-host-keys`, you'll have to install `nixos-anywhere` in a shell. I usually do this anyway.
	1. `nix-shell -p nixos-anywhere`
	2. `nixos-anywhere --copy-host-keys --flake '.#your-host' root@yourip`

### Documentation

- [Misterio77's nix-config](https://github.com/Misterio77/nix-config) - the holy grail of nix configs. <br>
- [home-manager](https://github.com/nix-community/home-manager) - userspace management. <br>
- [hardware](https://github.com/NixOS/nixos-hardware) - hardware quirks for various things.<br>
- [sops-nix](https://github.com/Mic92/sops-nix) - secrets management. <br>
- [impermanence](https://github.com/nix-community/impermanence) - forcing reproducability and clean boots. <br>
- [disko](https://github.com/nix-community/disko) - disk setups for machines. <br>
- [nixos-anywhere](https://github.com/nix-community/nixos-anywhere) - remote deployment of machines. <br>
- [nix.dev](https://nix.dev/index.html) - nix documentation <br>
- [Helpful Nix Tutorials and Docs](https://nixos-and-flakes.thiscute.world/) - great nix tutorials and documentation I need to work through. <br>
- [Docker Compose to Nix Config](https://github.com/aksiksi/compose2nix) - Easy way to convert existing docker compose files into Nix. <br>

## Automation Roadmap

Two parallel tracks for automating the homelab — pick one or run both side by side. Both tracks share the same **Phase 0** foundation.

### Phase 0: Shared Foundation (both tracks)

These steps are prerequisites regardless of which track you follow.

**Colmena on Local IPs:**

All servers are on-prem, so there's no reason to route Colmena through Tailscale. Replace hostname-based `targetHost` in `colmena.nix` with static IPs and centralize the IP map in one place (e.g. a shared attrset or `hosts.nix` file) so Colmena, Blocky DNS, and Traefik all reference the same source of truth.

| Host     | Subnet        | Current `targetHost` | New `targetHost`    |
| -------- | ------------- | -------------------- | ------------------- |
| saruman  | `10.1.8.0/24` | `saruman`            | static IP           |
| vader    | `10.2.1.0/24` | `vader`              | static IP           |
| phantom  | `10.1.8.0/24` | `phantom`            | static IP           |
| atreides | `10.1.8.0/24` | `atreides`           | static IP           |
| maul     | offsite       | `maul`               | static IP or VPN    |

- [ ] Switch Colmena `targetHost` values to static IPs
- [ ] Centralize IP mappings in a single `hosts.nix` attrset

**Monitoring Stack (Prometheus + Grafana):**

Shared across both tracks — observability is useful regardless of how deploys happen.

- [ ] Deploy Prometheus as a NixOS module (likely on atreides or a new VM)
- [ ] `prometheus-node-exporter` on every host for hardware/OS metrics
- [ ] Grafana dashboards for system health, disk usage, service status
- [ ] Alertmanager rules for disk full, service down, high load — notify via ntfy/email
- [ ] Optional: Loki for centralized log aggregation

---

### Track A: Traditional Ops (zero AI)

A fully deterministic, script-driven pipeline. Every decision is encoded in shell scripts, GitHub Actions workflows, and Nix expressions. No LLMs, no inference, no magic — just well-understood tools.

#### A1: Self-Hosted CI/CD Runner

Deploy a GitHub Actions self-hosted runner on **saruman** (Ryzen 5, Nvidia 1080 — already the beefiest box). This keeps builds on LAN with direct SSH access to every host.

- [ ] Add `services.github-runners` NixOS module to saruman's config
- [ ] Generate and sops-encrypt a GitHub runner registration token
- [ ] Create a dedicated SSH deploy key (sops-managed) that the runner uses to reach all hosts
- [ ] Label the runner (e.g. `self-hosted`, `nix`, `homelab`) for workflow targeting

#### A2: CI/CD Pipeline

Two GitHub Actions workflows:

**On Pull Request:**
```
nix flake check → colmena build (dry-build, no deploy)
```

**On Merge to `main`:**
```
nix flake check → cachix push → colmena apply → health check → notify
```

- [ ] Cachix binary cache integration to avoid redundant builds
- [ ] Selective deploys using Colmena tags (`--on @vm`, `--on @server`, `--on @gpu`)
- [ ] Notifications via ntfy, Slack webhook, or email on deploy success/failure
- [ ] Manual workflow dispatch for deploying a single host on demand

#### A3: Proxmox VM Automation

Declaratively manage VM lifecycle so spinning up a new NixOS server is a single PR.

- [ ] Terraform with the `bpg/proxmox` provider — define VMs (CPU, RAM, disk, network) as code
- [ ] Post-provision hook: `nixos-anywhere --copy-host-keys --flake '.#hostname' root@ip`
- [ ] Integrate `sops-check.sh` into the pipeline to auto-enroll new host keys
- [ ] Store Terraform state encrypted in the repo or in a remote backend
- [ ] Alternative: evaluate `nixos-generators` for building Proxmox-ready images directly from flake

#### A4: Health Checks and Rollback

- [ ] CI step after `colmena apply`: SSH into each host, verify systemd units are healthy
- [ ] Check critical services (Traefik, Blocky, Jellyfin, etc.) respond on expected ports
- [ ] On failure: `colmena apply --on @failed-host` with previous known-good revision, or `nixos-rebuild switch --rollback`
- [ ] CI tags each successful deploy commit so there's always a known-good ref to roll back to

#### A5: Full GitOps Loop

Close the loop — the repo becomes the single source of truth with zero manual intervention.

- [ ] Automated flake.lock update PR (already runs weekly) — auto-merge if `nix flake check` + `colmena build` pass
- [ ] Branch protection on `main`: require CI checks before merge
- [ ] Scheduled drift detection: nightly `colmena apply --evaluator streaming --verbose --what-if` dry-run, alert if actual state diverges from repo
- [ ] Self-healing: if drift is detected, auto-apply to bring hosts back in line (optional, aggressive)

#### Track A End State

```
git push → GitHub Actions (saruman runner) → nix flake check → cachix push
  → colmena apply → health checks → notify
  → on failure: auto-rollback + alert

Weekly: flake.lock update PR → auto-merge if green → full deploy cycle

New VM: Terraform apply → nixos-anywhere bootstrap → sops enroll → colmena apply
```

---

### Track B: AI-Augmented Ops

Layer AI into the operations workflow. The underlying infrastructure (Colmena, Prometheus, NixOS) stays the same — AI acts as an intelligent operator on top of it, handling triage, analysis, and generation of changes that still go through normal review.

#### B1: AI-Assisted Config Generation

Use an LLM to generate NixOS module configs from natural language descriptions, reducing boilerplate and speeding up new service onboarding.

- [ ] Local LLM on **saruman** (Ollama + CodeLlama/Deepseek-Coder or similar) — keep everything on-prem, no API keys
- [ ] Prompt templates for common tasks: "add a new NixOS service", "create a Colmena node", "write a disko config for X"
- [ ] CLI wrapper script: `./ai-gen service --name foo --port 8080` → generates a module scaffold
- [ ] All AI output lands in a feature branch for human review — never auto-merged

#### B2: Intelligent Alerting and Triage

Replace static Alertmanager rules with an AI layer that correlates metrics and provides actionable context when things break.

- [ ] Feed Prometheus alerts + recent metrics into a local LLM for root-cause analysis
- [ ] Alert enrichment: when Alertmanager fires, an AI summary is appended to the ntfy/Slack notification with probable cause and suggested remediation
- [ ] Runbook generation: AI produces step-by-step remediation based on the alert type and host context
- [ ] Correlation: group related alerts (e.g. high load + OOM + service restart) into a single incident summary

#### B3: Log Analysis with AI

Use AI to surface anomalies and patterns in logs that static rules would miss.

- [ ] Loki for centralized log aggregation (shared with Track A if both run)
- [ ] Periodic log summarization: cron job feeds recent logs to LLM, outputs a daily digest of notable events
- [ ] Anomaly detection: flag log patterns that deviate from baseline (e.g. sudden spike in auth failures, unusual systemd restarts)
- [ ] Query interface: natural language queries against logs — "what happened on phantom between 2am and 4am?"

#### B4: AI-Assisted PR Review and Drift Remediation

Use AI to review incoming Nix changes and auto-generate fixes for config drift.

- [ ] PR review bot: on new PR, LLM analyzes the Nix diff for common mistakes (missing `mkEnableOption`, wrong option types, security issues like open ports)
- [ ] Drift remediation: when scheduled drift detection (from Phase 0) finds divergence, AI generates a PR with the fix instead of just alerting
- [ ] Dependency analysis: when `flake.lock` updates, AI summarizes what changed upstream and flags breaking changes
- [ ] Nix evaluation error helper: on CI failure, AI reads the eval error and suggests a fix in a PR comment

#### B5: Conversational Homelab Management

A chat interface for managing the homelab through natural language.

- [ ] Local chatbot (Ollama-backed) with access to the repo, Prometheus API, and Colmena
- [ ] Commands like: "deploy the latest config to all VMs", "show me saruman's CPU usage this week", "what services are running on atreides?"
- [ ] Safety rails: destructive actions (deploy, rollback, VM delete) require explicit confirmation
- [ ] Context-aware: bot knows the repo structure, host inventory, and current Prometheus state

#### Track B End State

```
Alert fires → Prometheus → Alertmanager → AI triage (local LLM)
  → enriched notification with root cause + suggested fix
  → if auto-remediable: AI opens a PR → human approves → colmena apply

New service request → natural language → AI generates Nix module
  → PR opened → AI + human review → merge → deploy

Daily: AI log digest → anomaly report → flag issues before they alert

Drift detected → AI generates remediation PR → auto-deploy if approved
```
