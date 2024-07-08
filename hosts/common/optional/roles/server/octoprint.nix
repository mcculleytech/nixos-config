{ pkgs, config, ... }: {

	services.octoprint = {
		enable = true;
		openFirewall = true;
	};

	environment.systemPackages = with pkgs; 
	[
	  fswebcam
	  ustreamer
	];

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/octoprint"
	    ];
	  };
	};
}