{ pkgs, lib, config, ... }: 
let 
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json);
in 
{
	options = {
		jellyfin.enable =
			lib.mkEnableOption "enables jellyfin server";
	};

	config = lib.mkIf config.jellyfin.enable {

	services.jellyfin = {
		package = pkgs.unstable.jellyfin;
		enable = true;
		openFirewall = true;

		# NVENC/NVDEC on saruman's 1080 Ti (Pascal GP102): decodes h264, hevc
		# 8/10-bit, mpeg2, vc1, vp8, vp9; encodes h264 + hevc. No AV1 either way.
		hardwareAcceleration = {
			enable = true;
			type = "nvenc";
			device = "/dev/nvidia0";
		};
		transcoding = {
			enableHardwareEncoding = true;
			hardwareDecodingCodecs = {
				h264 = true; hevc = true; hevc10bit = true;
				mpeg2 = true; vc1 = true; vp8 = true; vp9 = true;
			};
			# Tonemapping runs as CUDA filters on NVENC; Pascal handles it.
			enableToneMapping = true;
		};
		# Settings above are the source of truth; overwrite the UI-written file.
		forceEncodingConfig = true;
	};

	# The module's DeviceAllow only lists hardwareAcceleration.device, which
	# closes the device cgroup — NVENC also needs the control/UVM nodes.
	systemd.services.jellyfin.serviceConfig.DeviceAllow = [
		"/dev/nvidiactl rw"
		"/dev/nvidia-uvm rw"
		"/dev/nvidia-uvm-tools rw"
		"/dev/nvidia-modeset rw"
	];


	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/jellyfin"
	    ];
	  };
	};

	  services.rpcbind.enable = true; # needed for NFS
	  boot.supportedFilesystems = [ "nfs" ];
	  systemd.mounts = let commonMountOptions = {
	    type = "nfs";
	    mountConfig = {
	      Options = "noatime";
	    };
	  };

	  in

	  [
	    (commonMountOptions // {
	      what = "${config.lab.hosts.truenas.ip}:/mnt/billthepony/movies";
	      where = "/var/lib/jellyfin/movies";
	    })
	    (commonMountOptions // {
	      what = "${config.lab.hosts.truenas.ip}:/mnt/billthepony/tv-shows";
	      where = "/var/lib/jellyfin/tv-shows";
	    })
	  ];

	  systemd.automounts = let commonAutoMountOptions = {
	    wantedBy = [ "multi-user.target" ];
	    automountConfig = {
	      TimeoutIdleSec = "600";
	    };
	  };

	  in

	  [
	    (commonAutoMountOptions // { where = "/var/lib/jellyfin/movies"; })
	    (commonAutoMountOptions // { where = "/var/lib/jellyfin/tv-shows"; })
	  ];

	};

}