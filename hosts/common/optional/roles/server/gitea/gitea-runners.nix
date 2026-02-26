{ config, pkgs, ... }:
let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../../secrets/git_crypt_traefik.json);
  giteaUrl = "https://source.${tr_secrets.traefik.homelab_domain}";
in
{
# A work in progress.
	sops.secrets = {
      gitea_actions_token = {
      sopsFile = ../../../../../vader/secrets.yaml;
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
					url = giteaUrl;
					tokenFile = config.sops.secrets."gitea_actions_token".path;
					enable = true;
					labels = [ 
					"ubuntu:latest:docker" 
					"native:host" 
				];
			};
				# flake-update = {
				# 	name = "flake-update";
				# 	url = giteaUrl;
				# 	tokenFile = config.sops.secrets."gitea_actions_token".path;
				# 	enable = true;
				# 	labels = ;
			# };
		};
	};

	# Persist Storage across reboots
	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/private"
	    ];
	  };
	};
}
