{ pkgs, config, lib, ... }: {


	options = {
		octoprint.enable =
			lib.mkEnableOption "enables octoprint server";
	};


	config = lib.mkIf config.octoprint.enable {

	# Pulls unstable, stable is broken atm
	nixpkgs.overlays = [
	  (final: prev: {
	    octoprint = pkgs.octoprint;
	  })
	];

	services.octoprint = {
		enable = true;
		openFirewall = true;
	};

	environment.systemPackages = with pkgs; 
	[
	  fswebcam
	  ustreamer
	];

	# Webcam service
	systemd.services.ustreamer = {
	  wantedBy = [ "multi-user.target" ];
	  description = "uStreamer for video0";
	  serviceConfig = {
	    Type = "simple";
	    ExecStart = ''${pkgs.ustreamer}/bin/ustreamer -p 8081 -s 0.0.0.0 --encoder=HW --persistent --drop-same-frames=30'';
	  };
	};

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/octoprint"
	    ];
	  };
	};

	networking.firewall.allowedTCPPorts = [ 8081 ];

	};
}