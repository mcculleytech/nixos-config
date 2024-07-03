{ pkgs, config, ... }: {
	services.jellyfin = {
		package = pkgs.unstable.jellyfin;
		enable = true;
		openFirewall = true;
	};


	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/jellyfin"
	    ];
	  };
	};
}