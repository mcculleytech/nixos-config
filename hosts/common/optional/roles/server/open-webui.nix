{ pkgs, lib, config, ... }:

{
 	options = {
		open-webui.enable =
			lib.mkEnableOption "enables open-webui for ollama";
	};

	config = lib.mkIf config.open-webui.enable {
		services.open-webui = {
			enable = true;
			host = "0.0.0.0";
			openFirewall = true;
			# Use the real state path instead of the symlink target.
			stateDir = "/var/lib/private/open-webui";
		};

		systemd.tmpfiles.rules = [
			"d /var/lib/private/open-webui 0750 open-webui open-webui -"
		];

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/private/open-webui"
	    ];
	  };
	};

	};
}
