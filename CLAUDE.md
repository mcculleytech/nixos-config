# overview
- This repository is an Infrastructure as Code repository, written in Nix.
- The structure of the project is as follows:
	  - `/disko` holds disk configurations for machines
	  - `/home` manages user home manager configurations
	  - `/hosts` manages system wide configurations.
	  - `/overlays` manages overlays for systems. 
	  - `/scripts` miscellaneous scripts for deployment/remote updates.
	  - `/secrets` secrets management for both sops and git-crypt.
	  - `/shells` nix shells. Largely unused at this point.
- `/hosts/common/global` holds various configurations applied across all hosts.
- `/hosts/common/optional` holds optional modules shared across all host types (docker, nvidia, opengl). Its `default.nix` is imported by every host.
- `/hosts/common/optional/roles/server` holds server-specific services. Its `default.nix` is imported by server hosts.
- `/hosts/common/optional/roles/workstation` holds workstation-specific services. Its `default.nix` is imported by workstation hosts (and saruman, which is both).
- The running ToDo list in the README should be the source of work. When done with a task already on there, mark it complete with the date. When discussing improvements make an entry.

## pre-merge / pre-commit checklist
Use the `/pre-merge` skill before merging a branch **or** before committing directly to master. It checks off completed README TODOs and AUTOMATION_ROADMAP milestones with today's date.

## host inventory
- All host IPs are defined in `hosts/common/hosts-data.nix` — this is the single source of truth.
- The NixOS module at `hosts/common/global/hosts.nix` exposes this data as `config.lab.hosts`.
- `colmena.nix` imports `hosts-data.nix` directly (outside the module system).
- When adding a new host or changing an IP, update only `hosts-data.nix` — all configs (prometheus, blocky, traefik, smokeping, colmena, etc.) reference it automatically.
- Never hardcode IPs in service configs. Use `config.lab.hosts.<name>.ip` or `hosts.<name>.ip` instead.

## new deployments
Use the `/deploy-service` skill. It encodes the full deployment workflow with approval gates.

## impermanence
- All hosts use impermanence with a blank root btrfs subvol snapshot. Persistent state lives under `/persist`.
- When a service requires subdirectories inside its state directory (e.g., `/var/lib/foo/data`), impermanence will bind-mount the parent directory but won't create subdirectories. If the service's pre-start script expects them to exist, it will fail.
- Fix this by adding `systemd.tmpfiles.rules` to create the required subdirectories before the service starts, e.g.: `"d /var/lib/foo/data 0755 foo foo -"`.
- Always check a new service's logs after first deploy — a crash loop with "directory does not exist" errors is a sign of this issue.

## monitoring
Prometheus and Grafana run on **atreides**. `node_exporter` is enabled globally on all hosts (port 9100). Use the `/add-monitoring` skill to wire up scraping and a Grafana dashboard for a new service.
