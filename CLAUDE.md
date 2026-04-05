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

## pre-merge checklist
- Before merging any branch to master, review and update the following files to reflect completed work:
  - `README.md` — check off completed TODO items with the date, add new items for follow-up work
  - `AUTOMATION_ROADMAP.md` — check off completed milestones, update pipeline diagrams if changed
- This ensures documentation stays in sync with the codebase and nothing is forgotten.

## host inventory
- All host IPs are defined in `hosts/common/hosts-data.nix` — this is the single source of truth.
- The NixOS module at `hosts/common/global/hosts.nix` exposes this data as `config.lab.hosts`.
- `colmena.nix` imports `hosts-data.nix` directly (outside the module system).
- When adding a new host or changing an IP, update only `hosts-data.nix` — all configs (prometheus, blocky, traefik, smokeping, colmena, etc.) reference it automatically.
- Never hardcode IPs in service configs. Use `config.lab.hosts.<name>.ip` or `hosts.<name>.ip` instead.

## new deployments
- All services use the `mkEnableOption` pattern: the service file defines an option (e.g., `myservice.enable`) gated by `lib.mkIf`, and is imported via a role's `default.nix`. Hosts toggle services on with `myservice.enable = true` in their `configuration.nix` — no individual file imports needed.
- For new service deployments, utilize the file `service.nix` as a template. Place the new service in the appropriate directory:
  - `hosts/common/optional/` — for modules usable by any host type (not server or workstation specific)
  - `hosts/common/optional/roles/server/` — for server-specific services
  - `hosts/common/optional/roles/workstation/` — for workstation-specific services
  - If unclear, verify with the user on location.
- Reference the nix documentation for the specific service at `https://search.nixos.org/options?channel=25.11&query=<service>` and ensure all the necessary options are set for the service to run properly and are network accessible over the LAN (and tailscale) as well as via a reverse proxy (traefik). Once you have a configuration planned, present it to the user for approval before writing the file.
- Once you have the service file written, add it to the `imports` list in the `default.nix` for the directory you placed it in. Then enable the service on the target host's `configuration.nix` with `myservice.enable = true`. If no host is given, prompt the user.
- Make an entry in the traefik `dynamic-config.nix` file. Creating entries for both `router` and `service` entries.
- Make a dns entry for the new service in the `blocky.nix` configuration file.
- Make an entry in the `homepage-dashboard.nix` file for the newly created service under the section that makes most sense. Verify with user before writing and provide reasoning.
- When adding persistence directories for services, use the attrset form (`{ directory = "..."; user = "..."; group = "..."; }`) with the service's user/group to ensure correct ownership on impermanence bind mounts.

## impermanence
- All hosts use impermanence with a blank root btrfs subvol snapshot. Persistent state lives under `/persist`.
- When a service requires subdirectories inside its state directory (e.g., `/var/lib/foo/data`), impermanence will bind-mount the parent directory but won't create subdirectories. If the service's pre-start script expects them to exist, it will fail.
- Fix this by adding `systemd.tmpfiles.rules` to create the required subdirectories before the service starts, e.g.: `"d /var/lib/foo/data 0755 foo foo -"`.
- Always check a new service's logs after first deploy — a crash loop with "directory does not exist" errors is a sign of this issue.

## monitoring
- Prometheus and Grafana run on **atreides**. Config files: `hosts/common/optional/roles/server/prometheus.nix` and `grafana.nix`.
- `node_exporter` is enabled globally on all hosts via `hosts/common/global/node-exporter.nix` (port 9100).
- To add monitoring for a new service:
  1. If the service has a built-in Prometheus metrics endpoint (like Traefik), enable it in the service's config and add a `scrapeConfigs` entry in `prometheus.nix` with the appropriate target and `job_name`.
  2. If the service needs a dedicated NixOS exporter (e.g., `services.prometheus.exporters.postgres`), enable it in the service's own `.nix` file, open the exporter's firewall port, and add a corresponding `scrapeConfigs` entry in `prometheus.nix`.
  3. Available NixOS exporters can be found at `https://search.nixos.org/options?channel=25.11&query=services.prometheus.exporters`.
  4. For Grafana dashboards, browse https://grafana.com/grafana/dashboards/ and import by ID via the Grafana UI. Key dashboard IDs: `1860` (Node Exporter Full), `17346` (Traefik).
