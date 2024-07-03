{ pkgs, config, ... }: {

	services.octoprint = {
		enable = true;
		openFirewall = true;
	};


	mjpg-streamer = {
	  enable = true;
	  # https://github.com/jacksonliam/mjpg-streamer/blob/master/mjpg-streamer-experimental/plugins/input_uvc/README.md
	  inputPlugin = "input_uvc.so --fps 1 -timeout 120";
	  outputPlugin = "output_http.so --www @www@ --nocommands --port 5050";
	};

	networking.firewall.allowedTCPPorts = [ 5050 ];

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/octoprint"
	    ];
	  };
	};
}