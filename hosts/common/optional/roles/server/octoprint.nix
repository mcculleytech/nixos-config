{ pkgs, config, ... }: {

	services.octoprint = {
		enable = true;
		openFirewall = true;
	};

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/octoprint"
	    ];
	  };
	};
}