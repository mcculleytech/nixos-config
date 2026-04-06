{ pkgs, lib, config, ... }:

{
 	options = {
		open-webui.enable =
			lib.mkEnableOption "enables open-webui for ollama";
	};

	config = lib.mkIf config.open-webui.enable {
		users.users.open-webui = {
			isSystemUser = true;
			group = "open-webui";
		};
		users.groups.open-webui = {};

		services.open-webui = {
			enable = true;
			host = "0.0.0.0";
			openFirewall = true;
			stateDir = "/var/lib/open-webui";
		};

		systemd.services.open-webui.serviceConfig = {
			DynamicUser = lib.mkForce false;
			PrivateUsers = lib.mkForce false;
			User = "open-webui";
			Group = "open-webui";
		};

		systemd.tmpfiles.rules = [
			"d /var/lib/open-webui 0750 open-webui open-webui -"
		];

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      { directory = "/var/lib/open-webui"; user = "open-webui"; group = "open-webui"; }
	    ];
	  };
	};

	};
}
