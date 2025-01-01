{ pkgs, lib, config, ... }:

{
 	options = {
		open-webui.enable =
			lib.mkEnableOption "enables open-webui for ollama";
	};

	config = lib.mkIf config.open-webui.enable {
		services.open-webui = {
			package = pkgs.unstable.open-webui;
			enable = true;
			host = "0.0.0.0";
			openFirewall = true;
		};



	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/open-webui"
	    ];
	  };
	};

	};
}
