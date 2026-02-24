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
			stateDir = "/var/lib/open-webui";
		};

		systemd.tmpfiles.rules = [
			"d /var/lib/private 0700 root root -"
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
