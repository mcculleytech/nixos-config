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

## new deployments
- For new service deployments, utilize the file located at `templates/services.nix` as a template. By default place the new service under `/hosts/common/optional/`. Add the import into the `default.nix` file for the `/hosts/common/optional` subdirectory and enable the service on the host specified in prompt. If no host is given, prompt the user. 
