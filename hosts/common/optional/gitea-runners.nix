{ config, pkgs, ... }:
{

	sops.secrets = {
      gitea_actions_token = {
      sopsFile = ../../vader/secrets.yaml;
      owner = config.systemd.services.gitea.serviceConfig.User;
    };

    sops.templates."gitea_actions_token".content = ''
      "${config.sops.placeholder.gitea_actions_token}"
    '';

	services.gitea-actions-runner = {
		instances = {
			hugo = {
				url = "https://source.mcculley.tech";
				tokenFile = config.sops.secrets.gitea_actions_token.path;
				enable = true;
			};
			flake-update = {
				url = "https://source.mcculley.tech";
				tokenFile = config.sops.secrets.gitea_actions_token.path;
				enable = true;
			};
		};
	};
  };
}