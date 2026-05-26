# Overview
[![built with nix](https://builtwithnix.org/badge.svg)](https://builtwithnix.org)

**A Quick Note of Thanks**
This repo was heavily influenced (and parts of it shamelessly taken from) [Misterio77's nix-config](https://github.com/Misterio77/nix-config) repo. Without his work, this repo would not be possible. 

This repository holds my NixOS infrastructure. I don't claim to be a Nix or NixOS expert. I don't work in DevOps and I'm very much still learning this language/package manager/ OS, this is just a hobby of mine that's been a lot of fun to play with.  With that being said, I hope you find something useful while you're here!

_One Config to rule them all, One Config to find them; One Config to bring them all and in the Nix Language bind them._

## Systems

| **Name** | Purpose                  											  							| Hardware                    |
| -------- | ---------------------------------------------------------------------------------------------- | --------------------------- |
| aeneas   | Personal Laptop <br> ironclaw agent (Nix-built, PostgreSQL + pgvector)  						| AMD Framework 13in          |
| saruman  | Local AI Server <br> Octoprint Server <br> Jellyfin Server <br> Paperless-ngx 				| AMD Ryzen 5 <br>Nvidia 1080 |
| vader    | Test Machine <br> Xonotic Server									  							| Proxmox VM                  |
| phantom  | Tailscale Subnet Router <br> Syncthing Server <br> Radicale Server <br> Blocky DNS Server  	| Proxmox VM                  |
| atreides | Blocky DNS Server <br> Homepage-dashboard <br> Traefik Reverse Proxy <br> Prometheus + Grafana | Proxmox VM                  |
| faramir  | Personal MacBook <br> Local LM Studio inference                                                | Apple Silicon MacBook       |

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
- bootstrap dev shell (`nix develop`) with deployment and secrets tooling
- LazyVim neovim config managed via home-manager (`xdg.configFile`) with nix-provided runtime deps
- `nix flake check` CI on PRs with auto-merge for weekly flake lock updates
- Claude Code skills (`.claude/skills/`) for repeatable workflows:
	- `/deploy-service` — end-to-end service deployment with approval gates (config, traefik, DNS, dashboard, secrets)
	- `/pre-merge` — checklist runner that syncs README and AUTOMATION_ROADMAP with completed work
	- `/add-monitoring` — wires Prometheus scraping and Grafana dashboards for a service

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
- [x] Standalone home manager config for wsl2 or Mac ✅ 2026-05-07
- [x] Add `mkEnableOption` modularity to desktop/workstation configs (matching server pattern) ✅ 2026-04-04

### Servers
- [x] Colmena setup
	- [x] Switch Colmena `targetHost` from Tailscale hostnames to local IPs — all boxes are on-prem, no need for Tailscale
- [x] KVM Server
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
- [ ] Mirror nixos-config to Gitea — GitHub remains primary, Gitea pulls as a read-only mirror
- [x] Jellyfin in Nix, decom ubuntu docker server ✅ 2024-08-01
- [ ] Arion for docker compose configurations
- [x] RSS feed server (Miniflux on phantom) ✅ 2026-03-12
- [x] n8n automation platform (native NixOS service, no Docker needed) ✅ 2026-03-17
- [x] Paperless-ngx document management (saruman, PostgreSQL + Tika OCR) ✅ 2026-03-17
- [x] Automate Proton Bridge on saruman — headless `protonmail-bridge --noninteractive` as a systemd-user service for alex, autostarts at boot via user-linger. Vault unlocked at boot by a sops-managed passphrase (`gnome_keyring_password`) piped to `gnome-keyring-daemon --components=secrets --unlock` (also a user service, ordered before Bridge). Existing kwallet-encrypted `vault.enc` was unmigratable — one-time CLI re-login created a fresh gnome-keyring-keyed vault. Bridge picked 1144 (IMAP) + 1026 (SMTP) since 1143/1025 had stale TIME_WAIT holds during the bootstrap; loopback-only, will be wired into the future hermes email MCP via `proton_bridge_user` + `proton_bridge_pass` sops scalars. Module: `hosts/common/optional/roles/server/protonmail-bridge.nix` ✅ 2026-05-26
- [x] saruman disk-pressure recovery + structural fix — 2026-05-26 the 233GB encryptedRoot filled (postgres crashed, nix daemon couldn't GC) while the 932GB encryptedHome sat near-empty. Fixes: relocated podman graphroot → `/home/podman/storage` and ollama home+models → `/home/ollama` (fixed `ollama` user + `ProtectHome=tmpfs`/`BindPaths` override, since the heavy container images + GGUF weights belong on the big disk, not competing with `/nix`); tightened `nix.gc` to daily + 7-day retention and added `min-free`/`max-free` (10/50 GB) so the daemon GCs in-band instead of crashing mid-build; cleaned ~133GB. ✅ 2026-05-26
- [x] ntfy push notification server (atreides, reverse-proxied via traefik) ✅ 2026-04-04
- [x] Auto-deploy pipeline — hourly systemd timer on saruman, staged VM→physical deploy with health checks and ntfy notifications ✅ 2026-04-04
	- [ ] Snapshot + restore stateful service config files on rollback — observed 2026-05-16 when `hermes-dashboard.service` failed `217/USER` (stale `User = "hermes"` referencing a long-deleted system user); auto-deploy rolled the nixos-system back to the prior build, but `/var/lib/hermes/.hermes/config.yaml` is written by upstream's NixOS module *during activation* and therefore reflected the post-deploy state. After rollback, the OLD hermes-agent binary started up reading the NEW config.yaml (with a `prometheus:` mcpServers entry pointing at a service that no longer existed in the rolled-back system), spent its first turn logging `MCP server 'prometheus' initial connection failed (attempt 1/3)` then giving up. Same risk applies to any service whose runtime config lives outside the nix store. Fix shape: `scripts/auto-deploy.sh` snapshots `~/.hermes/config.yaml` (and similarly stateful files for other services with the same pattern) before applying, restores from snapshot if `colmena apply` exits non-zero. Belt-and-suspenders: add a startup-time consistency check in hermes' systemd unit that confirms every `mcpServers.*` URL resolves to a running service, fails fast otherwise.
- [x] Prometheus + Grafana monitoring stack ✅ 2026-03-17
	- [x] OTEL collector + Loki + Tempo on atreides; Claude Code ships metrics/logs/traces via OTLP/HTTP through Traefik at `otel.home.mcculley.tech`. File-provisioned Grafana dashboard at `/d/claude-code`. ✅ 2026-05-21
	- [x] Grafana Alloy as a global log shipper — journald → Loki on atreides. Default-on knob (`lab.alloy.enable`) in `hosts/common/optional/alloy.nix`, auto-imported by every NixOS host. `host`/`unit`/`level`/`transport` promoted to stream labels. Shipping verified on atreides/phantom/saruman. ✅ 2026-05-22
		- [ ] Route vader Alloy via Tailscale — DMZ subnet (10.2.1.x) can't reach atreides:3100 directly. Use a per-host override or switch the endpoint to `atreides.tail5c738.ts.net:3100` for off-nix-subnet hosts.
		- [ ] Security-monitoring follow-ups — sshd auth pipeline stages, sudo invocation labels, `security.auditd.enable` for command-level audit, starter Grafana security dashboard. Started 2026-05-22 with centralized log collection; this layer is what turns it from "logs in one place" into "IR-investigation ready."
	- [x] Alertmanager + ntfy alert routing on atreides — `prometheus.nix` refactored into a `prometheus/` directory (`default.nix` scrape configs, `alertmanager.nix` routing, `alerts-disk.nix` rules). Alertmanager routes by `severity` label to three ntfy topics (`homelab-critical` urgent / `homelab-warnings` / `homelab-info`) via webhook to ntfy on 127.0.0.1:2586. First rules: `DiskCritical` (real-fs avail < 10GB) + `DiskFillingFast` (`predict_linear` of `/` free space crossing zero within 24h — fires while there's still time to react). New alert groups go in their own `alerts-<group>.nix`. Subscribe to the topics in the ntfy phone app. ✅ 2026-05-26
	- [ ] Additional exporters/monitors. Coverage cross-reference as of 2026-05-14 — Prometheus currently scrapes only `node` (all hosts), `traefik` (atreides), `blocky` (atreides+phantom). Everything else in this repo is unmonitored.
		- [ ] PostgreSQL exporter (`postgres_exporter`) — used by Gitea (vader), Miniflux (phantom), Paperless + Immich (saruman)
		- [ ] Redis exporter (`redis_exporter`) — used by Immich on saruman
		- [x] Blocky DNS metrics (built-in Prometheus endpoint, just needs scrape config) ✅ 2026-03-20
		- [ ] Gitea metrics on vader (built-in `/metrics` endpoint, enable in Gitea config)
		- [ ] Miniflux metrics on phantom (built-in `/metrics` endpoint, enable via `METRICS_COLLECTOR=1`)
		- [ ] Smartctl exporter (`smartctl_exporter`) — disk health on physical hosts
		- [ ] Blackbox exporter — HTTP/TCP endpoint uptime checks for all services
		- [ ] Tailscale client metrics (built-in `/metrics` endpoint via `tailscale set --webclient`, all hosts)
		- [ ] Systemd service alerting rules — alert on failed units across hosts
		- [ ] ntfy on atreides — `enable-metrics: true` in service.ntfy.settings, scrape on `:9090/metrics` (separate from the HTTP port)
		- [ ] Grafana self-scrape on atreides — built-in `/metrics` endpoint, useful for query/render latency
		- [ ] Smokeping on atreides — wrap with `smokeping_prober` exporter for latency series
		- [ ] Syncthing on phantom — built-in `/rest/system/stats` + `syncthing_exporter`
		- [ ] Jellyfin on saruman — built-in `/metrics` (requires API key in scrape config)
		- [ ] Immich on saruman — built-in Prometheus endpoint at `:8081/metrics` (separate from main API port)
		- [ ] Paperless-ngx on saruman — built-in `/metrics` endpoint in newer releases
		- [ ] n8n on saruman — set `N8N_METRICS=true` to expose `/metrics`
		- [ ] Open WebUI on saruman — `/metrics` endpoint in newer versions, gated on `ENABLE_PROMETHEUS_METRICS`
		- [ ] OctoPrint on saruman — `prometheus_exporter` plugin (community plugin, install via OctoPrint plugin manager)
		- [ ] Ollama on saruman — no native Prometheus; deploy `ollama-prometheus-exporter` (community) for token/req metrics
		- [x] NVIDIA GPU metrics — `services.prometheus.exporters.nvidia-gpu` wrapped into `hosts/common/optional/nvidia.nix` so any host with `nvidia.enable = true` auto-publishes on :9835. Today that's just saruman. Scrape job `nvidia-gpu` added to atreides's prometheus config. Surfaces `nvidia_smi_utilization_gpu_ratio`, `_memory_used_bytes`, `_temperature_gpu`, `_power_draw_watts`, per-process info. ✅ 2026-05-14
		- [ ] Hermes-agent on saruman — check if upstream exposes `/metrics`; if not, instrument the gateway for turn count / model dispatch / MCP error rates
		- [ ] Hermes MCPs (vault, agent-memory, signal, radicale, miniflux, gcal, escalator, prometheus) — each is a thin starlette app; add a `/metrics` route via `prometheus-client` exposing per-tool call counts + latency histograms. One-shot pattern that propagates across all eight MCPs.
		- [ ] vault-indexer on saruman — node_exporter `textfile` collector pattern: emit `vault_indexer_last_run_timestamp_seconds`, `vault_indexer_chunks_inserted_total`, `vault_indexer_errors_total` after each hourly run.
		- [ ] auto-deploy pipeline on saruman — same textfile-collector pattern: pipeline run timestamps, success/failure counts, per-host deploy duration.
		- [ ] Radicale on phantom — has a minimal Prometheus endpoint behind `WSGIPrometheus` middleware; lower priority (low traffic, low value) but trivial to wire.
- [x] Fix home-manager impermanence issue where the systemd units aren't mounted for hm.
- [x] Decommission maul — removed host config, colmena entry, sops keys, syncthing refs, and Systems table entry ✅ 2026-04-03
- [x] Decommission achilles — removed host config, sops keys, syncthing refs, SSH keys, and Systems table entry ✅ 2026-04-04


### Other
- [x] Move all machines to an `impermanence` setup ✅ 2024-03-08
 	- [x] Set as part of global config ✅ 2024-03-08
- [ ] Investigate copy host keys in nixos-anywhere breaking on first deployment run. Might be breaking due to impermanence.
- [ ] (tentative) AppArmor profile for hermes-agent on saruman — re-impose path-level isolation after collapsing the service identity into the `alex` user. Deny hermes-agent process access to `~/.ssh/`, `~/.config/sops/age/keys.txt`, browser cookies, etc. Closes the main remaining gap vs. dedicated-user setups while keeping bundled-skill auth-state simplicity.
- [ ] Nix upgrade-alert integration — surface a Signal/dashboard notification when a new NixOS release lands (e.g. 25.11 → 26.05) and when `nixos-rebuild` shows pending channel/flake updates older than N days. Probably another `hermes-plugin-*` that polls the NixOS releases feed (or `nix flake metadata` on the upstream `nixpkgs` input) and pings on stateVersion staleness vs. current stable. Build after `/spend`.
- [x] immutable users as default ✅ 2024-02-20
- [x] Clean up `flake.nix`
- [x] Fix GitHub Action that should autoupdate flake.lock ✅ 2024-08-01
	- [x] Auto-merge flake lock update PRs after CI passes ✅ 2026-04-03
	- [x] `nix flake check` CI workflow on PRs with branch protection on master ✅ 2026-04-03
	- [x] git-crypt decryption in CI for full config evaluation ✅ 2026-04-04
	- [x] Pin all GitHub Actions to commit SHAs (supply chain hardening) ✅ 2026-04-04
- [ ] Blocky DNS
	- [ ] Multiple Nodes connected via Redis (?)
	- [x] Multiple Servers ✅ 2024-03-20
- [ ] Organize different parts of NixOS & `home-manager` nix configs
	- [x] Role-based directory structure for Desktop and Server (`roles/server/`, `roles/workstation/`) with `mkEnableOption` patterns ✅ 2026-04-04
	- [x] Centralized host inventory (`hosts/common/hosts-data.nix`) — single source of truth for all IPs ✅ 2026-04-04
	- [ ] Further consolidation (e.g. single function for group-based settings)
- [ ] Make template files
	- [x] Service module template (`templates/service.nix`)
	- [ ] Host configuration template
	- [ ] Colmena node template
	- [ ] Home Manager module template
- [ ] Secrets organization (consolidate SOPS and git-crypt usage, standardize secret paths)
	- [ ] Scope SOPS secrets to the hosts that actually need them — today every machine can decrypt every secret (e.g. all hosts hold age keys that unlock `hermes_*`, `miniflux_*`, `traefik_*`, etc.). Split `secrets/*.yaml` per-host or move shared secrets to separate files keyed only to consumers, so a compromised non-hermes host can't read hermes/openrouter/oauth tokens.
- [x] `.gitignore` for defense-in-depth against accidental secret commits ✅ 2026-04-04
- [x] Security audit — verified no secrets leaked in public repo history ✅ 2026-04-04
- [ ] Dev environment `devShells` off root of project (Go, Python, Rust, C)
	- [x] C maldev shell (`shells/c-maldev.nix`) ✅ 2026-04-03
	- [x] Go dev shell (`shells/go-dev.nix`) ✅ 2026-04-03
- [ ] Offensive security attack box configuration
	- [ ] New host or role with offsec tooling (nmap, Burp Suite, Metasploit, Wireshark, etc.)
	- [ ] Wordlists and SecLists provisioning
- [ ] Offsec dev shells (`shells/`)
	- [ ] `recon.nix` — reconnaissance tools (nmap, amass, subfinder, httpx, nuclei, etc.)
	- [ ] `exploit.nix` — exploitation frameworks and utilities (metasploit, sqlmap, etc.)
	- [ ] `post-exploit.nix` — post-exploitation / lateral movement tools (chisel, ligolo, etc.)
	- [ ] `web.nix` — web app testing (Burp, ffuf, gobuster, feroxbuster, etc.)
	- [ ] `wireless.nix` — wireless auditing (aircrack-ng, bettercap, etc.)
	- [ ] `osint.nix` — OSINT gathering (theHarvester, Maltego, Recon-ng, etc.)
- [ ] Maldev shells (`shells/`)
	- [x] `maldev-c.nix` — C/C++ toolchain (gcc, clang, mingw-w64 cross-compiler, make, cmake, nasm) ✅ 2026-04-03
	- [x] `maldev-go.nix` — Go toolchain (Go, gopls, delve, garble) ✅ 2026-04-03
- [x] ironclaw cross-platform NixOS/nix-darwin module (`hosts/common/optional/ironclaw.nix` + `ironclaw-linux.nix`) ✅ 2026-05-08
	- [x] PostgreSQL 17 + pgvector provisioning on Linux ✅ 2026-05-08
	- [x] ironclaw enabled on aeneas (Linux, Nix-built) ✅ 2026-05-08
	- [x] Pivot away from ironclaw on all hosts; `lab.ironclaw.enable` left as default `false`, package derivation retained for future use ✅ 2026-05-11
- [ ] Personal Agent Infrastructure
	- [x] Phase 1: Shared agent memory on saruman (PostgreSQL + pgvector + MCP gateway, Tailscale-bound, bearer-token auth) ✅ 2026-05-11
	- [ ] Phase 2: Obsidian Sync via `obsidian-headless` on saruman; vault MCP server(s) for read/write access
	- [ ] Phase 3: Hermes agent on saruman via upstream `NousResearch/hermes-agent`, OpenRouter single-model with user-driven `/model` slash overrides, Signal I/O via dedicated number on signal-cli
		- [x] Hermes external-service auth — GitHub fine-grained PAT (`hermes_github_pat`) wired as `GH_TOKEN`, `pkgs.gh` on hermes runtime PATH for the bundled github-* skills; Google Calendar OAuth (calendar scope, app published to Production) via `hermes_google_client_secret` sops template + persistent `google_token.json` under `/var/lib/hermes/.hermes/` ✅ 2026-05-12
		- [x] Pivot Hermes to OpenRouter — single sub-key (`OPENROUTER_API_KEY`, capped via `scripts/openrouter-bootstrap.sh`) handles every model call; default = `deepseek/deepseek-v4-pro` pinned to ZDR US-HQ providers via `extra_body.provider.data_collection=deny` + `only=[parasail, atlas-cloud, deepinfra, novita, venice]`; `/model` slash aliases (`opus`/`pro`/`think`/`qwen`/`flash`/`deep`/`local`/`mac`) for per-session overrides with 2 h idle reset; tried orchestrator+delegate pattern first and abandoned (hermes-agent enforces subagent toolset ⊆ parent, so cheap orchestrators with full tool buffet never delegate) ✅ 2026-05-13
		- [x] `vault_query_frontmatter` tool on vault-mcp — Dataview-style queries over YAML frontmatter + inline `#tag` refs with folder/where/has_tag/after/before/name_glob/sort filters; pulled in PyYAML for proper frontmatter parsing ✅ 2026-05-13
		- [x] `escalator-mcp` — `consult_expert(question, model=…)` tool for one-shot frontier-model consults within a turn, whitelist-bounded to Opus 4.7 Fast / V4 Pro / Gemini 3.1 Pro Preview ✅ 2026-05-13
		- [x] `gcal-mcp` — Google Calendar wrapper reusing the bundled `google-workspace` skill's existing OAuth (`google_token.json` + `google_client_secret.json`); read-only `gcal_calendar_list` + `gcal_event_list` exposed as MCP tools; gcal_mcp service user joins the `hermes` group with mode 0440 on the credential files ✅ 2026-05-13
		- [x] i18n locales patch — upstream's `pyproject.toml` + nix derivation forget to ship `locales/`, so `agent/i18n.py` returns raw keys (`gateway.model.switched` etc.) for every slash-command response. Worked around with a `sitecustomize.py` injected via `PYTHONPATH` + `HERMES_LOCALES_DIR` that monkey-patches `_locales_dir()` at Python startup ✅ 2026-05-13
		- [ ] `github-mcp` — mirror `gcal-mcp` pattern wrapping the `gh` CLI for reliable repo/PR/issue queries from any agent context (bundled github-* skills work in interactive chat but not from cron / minimal-toolset contexts)
		- [x] **Run hermes-agent as `alex`** instead of dedicated `hermes` system user — eliminates skill-friction workarounds (bundled `claude-code`/`google-workspace`/`github-*` skills all assume operator auth at well-known `~/.x` paths). The `hermes` group survives as a shared-secret group (alex + escalator_mcp + gcal_mcp members; secrets owner=alex group=hermes mode 0440). One-shot activation chown migrated `/var/lib/hermes` from `hermes:hermes` to `alex:hermes`. AppArmor profile remains as a tentative follow-up for re-imposing path-level isolation ✅ 2026-05-13
		- [x] **Hermes default model → Gemini 2.5 Flash via BYOK** on alex's Google AI Studio account ($10/mo Pro-subscription credit covers ~all routine use). DeepSeek V4 Pro available as `/model deep` for tool-heavy turns. Provider pinned to `google-ai-studio` with `allow_fallbacks=false` so quota exhaustion hard-errors rather than silently routing to paid OR credit; `fallback_model = deepseek/deepseek-v4-flash` on the existing ZDR provider pool handles transient Google failures ✅ 2026-05-14
		- [x] **`hermes-plugin-intel`** — `/intel` slash command. Pulls last-24h Miniflux entries, two-pass triage + synthesis via Gemini Flash Lite (BYOK = effectively free), categorized brief grouped by cve/tooling/apt/advisory/opsec/defense/research. English-only by default, per-feed cap 5, sort by relevance score. Adds a short-form-content-ideas section when items qualify ✅ 2026-05-13
		- [x] **`hermes-plugin-today`** — `/today` slash command + daily-note creator. Creates today's Obsidian daily note from the Templater template (idempotent), pulls events from both radicale calendars (ToDo + General) and all gcal calendars sorted by access role, pulls radicale tasks (14-day window filter), walks `05 - personal notes/YYYY/MM/*.md` for open `- [ ]` lines tagged `#tasks` (mirrors the in-Obsidian Dataview query). One Gemini Flash Lite synth call for the shape-of-day one-liner; `raw` arg skips it, `no-note` arg skips the daily-note creation ✅ 2026-05-14
		- [x] **`hermes-plugin-spend`** — `/spend [today|week|month|mtd]` slash command. Three-stage evolution:
			- **v1 (2026-05-14)**: OR `/activity` per-day fetch loop with UTC-completion gating (built around the false assumption that `?date=YYYY-MM-DD` was the only way to query, and it 400s on today).
			- **v2 (2026-05-14 same day)**: rewritten to source from hermes' own `state.db` (sqlite, real-time per-session cost from `estimated_cost_usd`). Numbers turned out wrong — state.db only writes at session-end, so mid-session usage is invisible. Caught when OR dashboard showed $3.10 deepseek but `/spend` reported $0.12.
			- **v3 (2026-05-15)**: hybrid. OR `/activity` (no date param) IS real-time and returns ~30 days of rows including yesterday-in-progress. Plugin uses it as primary; state.db only for `billing_provider ∈ {'anthropic', 'custom'}` (the calls that never transit OR). Buckets: `openrouter credit`, `google (BYOK via OR)`, `anthropic (direct)`, `local (free)`. Numbers reconcile with OR dashboard exactly.
			- **v4 (2026-05-16)**: today-window fix. OR `/activity` actually has a multi-hour lag for the *current* UTC day — v3 worked because the "today" I'd tested was about-to-roll. For real today: compute today's OR-credit dollars from `/credits.total_usage` minus historical `/activity` sum (the delta is exact); pull today's state.db OR sessions for per-model partial view; remainder shows as `(other OR-credit today, no breakdown yet)`. Footer notes the per-row breakdown is partial.
			
			Plus: Google Pro $10/mo budget meter (MTD BYOK vs ceiling), three-way `Total spend (paid) across OpenRouter + Google + Anthropic` rollup line, daily breakdown attributed to the actual session start date ✅ 2026-05-14, evolved through 2026-05-16
		- [x] **`/model` alias system** — `/intel <alias>`, `/today <alias>`, plus `/model` bare-call shows the alias table prepended. `pkgs/hermes-plugin-common/aliases.py` provides `_model_aliases()` / `_resolve_alias()` loaded by both plugins from `~/.hermes/config.yaml`'s `model_aliases:` block (same source `/model <name>` switching uses). New `default` alias tracks `cfg.defaultModel` so `/model default` always points at the current configured default. `sitecustomize.py` patches `GatewayRunner._handle_model_command` to render the alias table on bare-`/model` invocations (Signal has no picker; this is the discoverability hook) ✅ 2026-05-14
		- [x] **`hermes-skill-obsidian` (Nix-packaged)** — `obsidian-vault-policy` skill at `pkgs/hermes-skill-obsidian/SKILL.md`, symlinked into `~/.hermes/skills/note-taking/obsidian-vault-policy/` via tmpfiles. Replaces an unused agent-created skill (`obsidian-notes-management`, use_count=0). Covers the `mcp_vault_*` vs filesystem-tools preference, mandates explicit approval before any vault write, and — crucially — documents the keyword-vs-semantic search split: vault-mcp's `vault_search` is grep-style; `mcp_agent_memory_memory_search(project="vault", ...)` is pgvector semantic via `vault-indexer`'s embedded chunks ✅ 2026-05-14
		- [x] **Module split + cleanup** — `hermes-agent/default.nix` (692 lines) refactored into `default.nix` (options + top-level wiring), `secrets.nix` (sops + env template), `state.nix` (tmpfiles), and `service.nix` (services.hermes-agent + systemd overrides). Dead `hermes-state-chown` one-shot migration script removed. `MESSAGING_CWD` env var unset (was triggering deprecation warning every startup) — replaced by `terminal.cwd` in settings. `google_chat-platform` bundled plugin disabled via `plugins.disabled` (the wheel ships it but the Platform enum doesn't include `google_chat`, every startup logged a noisy warning) ✅ 2026-05-14
		- [x] Hermes-sphere simplification sweep — deleted the disabled morning-briefing cron scaffolding (`secrets/hermes-cron-jobs.yaml`, `hermes-cron-seed` activation script, `morningBriefing*` options), pruned dead model aliases (qwen / think / mac), extracted `SOUL.md` and `sitecustomize.py` from inline nix heredocs to sibling files for easier editing. Net: hermes-agent module shrank ~270 lines ✅ 2026-05-14
	- [ ] Phase 4: Scheduled embedding/summarization jobs, task-capture workflows, web dashboard
		- [x] Schedule `/today` as a 6 AM daily cron via `no_agent: true` so the briefing lands before alex picks up his phone. Four gotchas, all fixed 2026-05-15:
			1. **Script must be a regular file**, not a symlink — hermes' `_validate_cron_script_path` resolves symlinks before checking containment, so a `L+ ... → /nix/store/...` link gets rejected as "escapes the scripts directory". Solution: `system.activationScripts.hermes-cron-scripts` in `hermes-agent/state.nix` `cp`'s `${pkgs.hermes-plugin-today}/scripts/morning-today.py` into `$HERMES_HOME/scripts/` as a real file on every activation.
			2. **`hermes cron create` writes to the invoker's `HERMES_HOME`**, NOT a shared location. Running it as alex without `HERMES_HOME=/var/lib/hermes/.hermes` writes the job to `/home/alex/.hermes/cron/jobs.json`, which the systemd daemon never reads. Always prefix: `HERMES_HOME=/var/lib/hermes/.hermes hermes cron create ...` when registering daemon-fired jobs.
			3. **`SIGNAL_HOME_CHANNEL` must be a single identifier**, not the multi-form `hermes_allowlist` value (`+phone,uuid`). Standalone-send fallback strips non-digits and concatenates → mangled recipient like `+19313742611<digits-of-uuid>` → `UNREGISTERED_FAILURE`. Solution: new `hermes_self_number` sops scalar with just `+phone`, used for `SIGNAL_HOME_CHANNEL` in the env template. `hermes_allowlist` stays multi-form for inbound matching.
			4. **The standalone wrapper script must load the plugin as a package**, not a bare module. Plugin's `__init__.py` uses relative imports (`from .aliases import …`); a naive `spec_from_file_location("hermes_plugin_today", init_path)` loads it as a top-level module and the relative import fails with `ModuleNotFoundError: No module named 'hermes_plugin_today'`. Solution: mirror hermes' own loader pattern — pass `submodule_search_locations=[plugin_dir]`, set `mod.__package__` + `mod.__path__`, and register in `sys.modules[name] = mod` BEFORE `exec_module()`.
			
			Plugin source `pkgs/hermes-plugin-today/morning-today.py` loads the today plugin module via importlib (as a package — see #4) and runs `_run_today` async. Delivers to alex's own number → self-DM ("Note to Self"). Final job ID: `e3f9ec6f3efc` ✅ 2026-05-14 (broken), fully working 2026-05-15
		- [ ] `/claude-code` as a deterministic plugin (mirror `/today`/`/intel`/`/spend` pattern) — currently the bundled skill is a system-prompt-prefix injection that the model has discretion to ignore (V4 Pro bypassed it via `terminal` calls when tested). A plugin handler that shells out to `claude -p` directly closes that hole and inherits alex's Anthropic subscription billing.
		- [x] **Migrate all 8 MCPs Python → Go + reorganize under `roles/server/mcp/`** — every MCP (miniflux, escalator, prometheus, vault, signal, radicale, gcal, agent-memory) rewritten in Go using `github.com/mark3labs/mcp-go` (Streamable-HTTP, bearer auth, tailnet bind — same wire behavior, 1:1 tool parity). NixOS modules moved from `roles/server/<name>-mcp/` into a dedicated `roles/server/mcp/<name>/` subdir; package sources stay at `pkgs/<name>-mcp/` (now `buildGoModule`). Ports + option names (`<name>-mcp.enable`) preserved. Migration order simplest→hardest, verified per-MCP (health + hermes TCP sessions) before the next. Convention codified in CLAUDE.md "MCP conventions" + `08 - homelab/mcp-deployment-pattern.md`: new MCPs are Go. Notable per-MCP gotchas: signal uses pure-Go `modernc.org/sqlite` (no cgo); gcal reads Python `google-auth`'s on-disk token format via an in-code shim (no file conversion); radicale uses `emersion/go-webdav` (+ a small `davDelete` helper for the DELETE the lib omits); agent-memory uses `pgx/v5` + `pgvector-go`. ✅ 2026-05-26
		- [x] **agent-memory dedup: structured tool results + UNIQUE `source` index + true upsert** — the Go port initially returned text-only tool results (`NewToolResultText`), which broke vault-indexer's `call_tool` (it parses `structuredContent`); switched all 8 MCPs' result helper to `NewToolResultStructured` wrapping non-object values under `result` (FastMCP convention). Added a partial `UNIQUE INDEX memories_source_uniq ON memories(source) WHERE source IS NOT NULL` + converted `memory_insert` to `ON CONFLICT (source) DO UPDATE` + `ORDER BY source, created_at DESC` tiebreaker on `memory_list_by_source` + defensive dup-cleanup in the indexer's snapshot. Net: duplication is now structurally impossible. Row count stable at ~12.7k across consecutive runs (was ballooning by ~360/run). Residual ~480 upserts/run churn (delete+reinsert of a stable set — wasteful Ollama re-embedding, bounded by the index) is a minor follow-up, not a leak. ✅ 2026-05-26
		- [ ] Collapse `signal-mcp` / `miniflux-mcp` / `radicale-mcp` into hermes plugins (in-process Python) — each is a thin HTTP client around a REST API and doesn't benefit from process isolation; the MCP-per-integration pattern is overhead. Keep `agent-memory-mcp` / `vault-mcp` / `escalator-mcp` / `gcal-mcp` as services (real isolation requirements or fat dep trees). NOTE 2026-05-26: now that all MCPs are Go single-binaries the "fat dep tree" half of the rationale is weaker; revisit whether this collapse is still worth it.
		- [ ] vault-indexer churn follow-up — ~480 chunks/run fail the sha-match and get re-embedded despite stable content. Investigate chunk non-determinism (chunk-boundary or whitespace handling) so steady-state upserts drop to ~0 and stop burning hourly Ollama cycles. Not a disk risk (UNIQUE index bounds row count). Surfaced 2026-05-26.
		- [ ] Token rotation hygiene — rotate `tavily_api_key`, `lmstudio_api_key`, `future_hermes_radicale`, `future_hermes_gcal` (all surfaced in transcripts during debugging; tailnet-only attack surface but worth cycling).
		- [ ] MCP supervisor retry/backoff fix — `tools.mcp_tool` currently retries an MCP 5× then logs "failed after 5 reconnection attempts, giving up" and **never tries again** for the life of the hermes process. Any MCP restart (sops reload, deploy, manual restart) silently breaks tool calls until hermes itself is restarted — observed 2026-05-14 when all 7 MCPs disconnected at 10:05 and stayed dead even though every MCP was healthy 60s later. Need infinite retry with exponential backoff (or at least a periodic ping-and-reconnect loop) so the system self-heals.
		- [ ] Mac model alias matrix — current `mac` alias hard-pins to `mlx-community/gemma-4-26b-a4b-it` and isn't even nix-managed (lives in alex's config.yaml from a long-ago `hermes model` CLI invocation). LM Studio on aeneas (`100.90.82.127:1234`) currently has 6 instruction models loaded (gemma-4 26b/31b variants, qwen3-coder-30b, qwen3.6-27b, gemma-4 non-instruct flavors). Wire a NixOS attrset option `cfg.macModels = { mac = "..."; mac-coder = "..."; mac-large = "..."; mac-qwen = "..."; }` and iterate it into `services.hermes-agent.settings.model_aliases` so each entry exposes a distinct `/model <slug>`. LM Studio validates the model name against what's loaded, so the right model must be loaded on aeneas before the corresponding alias resolves. Endpoint via separate `cfg.macBaseUrl` option so a tailnet IP change is a one-knob update.
		- [ ] GPU metrics Grafana dashboard — `nvidia-gpu` scrape is live on atreides since 2026-05-14 but no panels yet. Build at minimum: VRAM-pressure gauge (`memory_used / memory_total`), temperature trend (with throttling threshold line at 75°C), utilization heatmap, power-draw burst rate. Alert on sustained `>0.85` VRAM (Ollama + Jellyfin transcodes + Immich ML share the GPU; OOM is real risk).
		- [ ] Package `ultraworkers/claw-code` when upstream ships a flake — currently no `flake.nix` in repo, no nixpkgs entry, no community `claw-code-nix` wrapper. 191k★ active repo (multiple commits daily) — packaging ourselves means chasing a moving target. Wait for sadjow-style auto-updating-flake equivalent, then add as a flake input + bind to `home.packages` next to claude-code/opencode. Saw 2026-05-15.
	- [x] Homelab MCPs (agent-memory, vault, signal, radicale, miniflux) wired into Claude Code on saruman at user scope, authenticated via the per-MCP `claude-personal` sops tokens ✅ 2026-05-12
		- [ ] Add gcal-mcp + escalator-mcp to Claude Code's MCP server list (new `claude_personal_gcal` + `claude_personal_escalator` sops tokens, mirror the existing pattern)
		- [x] **`prometheus-mcp`** — read-only Prometheus + Alertmanager MCP at `pkgs/prometheus-mcp/`, 10 tools (`query`, `query_range`, `alerts`, `rules`, `targets`, `label_names`, `label_values`, `series`, `metric_metadata`, `runtime_info`, plus optional `alertmanager_alerts` / `alertmanager_silences` gated on `alertmanagerUrl`). Runs as `prometheus_mcp` system user on saruman tailnet IP:4287. Talks to atreides:9090 directly (no upstream auth — tailnet-only). Bearer-auth token map in sops includes `hermes` (for hermes-agent) + `claude_personal` (for alex's interactive Claude Code sessions, user-scope). Mirrors the pattern of every other MCP in this repo ✅ 2026-05-14
- [ ] Full Homelab Automation — Traditional Ops & AI-Augmented Ops (see [Automation Roadmap](AUTOMATION_ROADMAP.md))
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
7. Enter the bootstrap dev shell (includes `nixos-anywhere`, `colmena`, `sops`, `age`, `ssh-to-age`, etc.):
	1. `nix develop`
	2. `nixos-anywhere --copy-host-keys --flake '.#your-host' root@yourip`
	3. For subsequent deploys, use `colmena apply --on hostname`

### Pre-Commit Hook

A pre-commit hook verifies that staged secrets are properly encrypted before allowing a commit. It checks:
- **SOPS files** — any file matching a `path_regex` in `.sops.yaml` must contain the `sops:` metadata key
- **git-crypt files** — any file matching `secrets/git_crypt*` must have the `filter=git-crypt` attribute set in `.gitattributes`

To install:
```bash
./scripts/setup-hooks.sh
```

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
