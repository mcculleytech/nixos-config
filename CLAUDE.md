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
- `/hosts/common/optional` holds optional services broken further into `servers` and `workstations` for specific configurations for those machines
- The running ToDo list in the README should be the source of work. When done with a task already on there, mark it complete with the date. When discussing improvements make an entry.

## new deployments
- For new service deployments, utilize the file `service.nix` as a template. By default place the new service under `optional` subdirectory for servers unless the configuration appears to be more desktop related in which case verify with the user on location. Reference the nix documentation for the specific service at `https://search.nixos.org/options?channel=25.11&query=<service>` and ensure all the necessary options are set for the service to run properly and are network accessible over the LAN (and tailscale) as well as via a reverse proxy (traefik). Once you have a configuration planned, present it to the user for approval before writing the file. 
- Once you have the service file written, add the file to the `imports` section into the `default.nix` file for the `optional` subdirectory and enable the service on the host specified in prompt. If no host is given, prompt the user. 
- Make an entry in the traefik `dynamic-config.nix` file. Creating entries for both `router` and `service` entries. 
- Make a dns entry for the new service in the `blocky.nix` configuration file. 
- Make an entry in the `homepage-dashboard.nix` file for the newly created service under the section that makes most sense. Verify with user before writing and provide reasoning. 
- When adding persistence directories for services, use the attrset form (`{ directory = "..."; user = "..."; group = "..."; }`) with the service's user/group to ensure correct ownership on impermanence bind mounts.

## monitoring
- Prometheus and Grafana run on **atreides**. Config files: `hosts/common/optional/roles/server/prometheus.nix` and `grafana.nix`.
- `node_exporter` is enabled globally on all hosts via `hosts/common/global/node-exporter.nix` (port 9100).
- To add monitoring for a new service:
  1. If the service has a built-in Prometheus metrics endpoint (like Traefik), enable it in the service's config and add a `scrapeConfigs` entry in `prometheus.nix` with the appropriate target and `job_name`.
  2. If the service needs a dedicated NixOS exporter (e.g., `services.prometheus.exporters.postgres`), enable it in the service's own `.nix` file, open the exporter's firewall port, and add a corresponding `scrapeConfigs` entry in `prometheus.nix`.
  3. Available NixOS exporters can be found at `https://search.nixos.org/options?channel=25.11&query=services.prometheus.exporters`.
  4. For Grafana dashboards, browse https://grafana.com/grafana/dashboards/ and import by ID via the Grafana UI. Key dashboard IDs: `1860` (Node Exporter Full), `17346` (Traefik).
