{ config, pkgs, ... }:
{
# A work in progress. Decided to shelve this project for the time being (2-10-24)
	sops.secrets = {
      gitea_actions_token = {
      sopsFile = ../../vader/secrets.yaml;
      owner = config.systemd.services.gitea.serviceConfig.User;
    	};
	};

    sops.templates."gitea_actions_token".content = ''
      "${config.sops.placeholder.gitea_actions_token}"
    '';

	services.gitea-actions-runner = {
		instances = {
			hugo = {
				name = "hugo";
				url = "https://source.mcculley.tech";
				tokenFile = config.sops.secrets."gitea_actions_token".path;
				enable = true;
				labels = [ 
					"ubuntu:latest:docker" 
					"native:host" 
				];
			};
			# flake-update = {
			# 	name = "flake-update";
			# 	url = "https://source.mcculley.tech";
			# 	tokenFile = config.sops.secrets."gitea_actions_token".path;
			# 	enable = true;
			# 	labels = ;
			# };
		};
	};
}