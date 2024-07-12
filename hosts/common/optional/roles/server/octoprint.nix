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

	# Webcam service
	systemd.services.ustreamer = {
	  wantedBy = [ "multi-user.target" ];
	  description = "uStreamer for video0";
	  serviceConfig = {
	    Type = "simple";
	    ExecStart = ''${pkgs.ustreamer}/bin/ustreamer -p 8081 --encoder=HW --persistent --drop-same-frames=30'';
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
}