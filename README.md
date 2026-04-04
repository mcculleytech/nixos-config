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
| saruman  | Local AI Server <br> Octoprint Server <br> Jellyfin Server <br> Paperless-ngx 				| AMD Ryzen 5 <br>Nvidia 1080 |
| vader    | Test Machine <br> Xonotic Server									  							| Proxmox VM                  |
| phantom  | Tailscale Subnet Router <br> Syncthing Server <br> Radicale Server <br> Blocky DNS Server  	| Proxmox VM                  |
| atreides | Blocky DNS Server <br> Homepage-dashboard <br> Traefik Reverse Proxy <br> Prometheus + Grafana | Proxmox VM                  |

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
- [ ] Standalone home manager config for wsl2 or Mac
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
- [x] Jellyfin in Nix, decom ubuntu docker server ✅ 2024-08-01
- [ ] Arion for docker compose configurations
- [x] RSS feed server (Miniflux on phantom) ✅ 2026-03-12
- [x] n8n automation platform (native NixOS service, no Docker needed) ✅ 2026-03-17
- [x] Paperless-ngx document management (saruman, PostgreSQL + Tika OCR) ✅ 2026-03-17
- [ ] Automate Proton Bridge on saruman (currently running manually in tmux; needs kwallet/keyring service dependency to run as a systemd user service on boot)
- [x] Prometheus + Grafana monitoring stack ✅ 2026-03-17
	- [ ] Additional exporters/monitors:
		- [ ] PostgreSQL exporter (`postgres_exporter`) — used by Gitea, Miniflux, Paperless, Immich
		- [ ] Redis exporter (`redis_exporter`) — used by Immich on saruman
		- [x] Blocky DNS metrics (built-in Prometheus endpoint, just needs scrape config) ✅ 2026-03-20
		- [ ] Gitea metrics (built-in `/metrics` endpoint, enable in Gitea config)
		- [ ] Miniflux metrics (built-in `/metrics` endpoint, enable via `METRICS_COLLECTOR=1`)
		- [ ] Smartctl exporter (`smartctl_exporter`) — disk health on physical hosts
		- [ ] Blackbox exporter — HTTP/TCP endpoint uptime checks for all services
		- [ ] Tailscale client metrics (built-in `/metrics` endpoint via `tailscale set --webclient`, all hosts)
		- [ ] Systemd service alerting rules — alert on failed units across hosts
- [x] Fix home-manager impermanence issue where the systemd units aren't mounted for hm.
- [x] Decommission maul — removed host config, colmena entry, sops keys, syncthing refs, and Systems table entry ✅ 2026-04-03
- [x] Decommission achilles — removed host config, sops keys, syncthing refs, SSH keys, and Systems table entry ✅ 2026-04-04


### Other
- [x] Move all machines to an `impermanence` setup ✅ 2024-03-08
 	- [x] Set as part of global config ✅ 2024-03-08
- [ ] Investigate copy host keys in nixos-anywhere breaking on first deployment run. Might be breaking due to impermanence.
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
	- [ ] Further consolidation (e.g. single function for group-based settings)
- [ ] Make template files
	- [x] Service module template (`templates/service.nix`)
	- [ ] Host configuration template
	- [ ] Colmena node template
	- [ ] Home Manager module template
- [ ] Secrets organization (consolidate SOPS and git-crypt usage, standardize secret paths)
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
