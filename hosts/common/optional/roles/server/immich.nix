	{ pkgs, lib, config, ... }:
	{

	options = {
		immich.enable =
			lib.mkEnableOption "enables immich server";
	};

	config = lib.mkIf config.immich.enable {

	  services.immich = {
				enable = true;
				openFirewall = true;
				host = "0.0.0.0";
		};


		environment.persistence = {
  	  "/persist" = {
  	  hideMounts = true;
  	    directories = [
  	      "/var/lib/immich"
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
        what = "10.1.8.4:/mnt/billthepony/pictures";
        where = "/var/lib/immich";
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
      (commonAutoMountOptions // { where = "/var/lib/immich"; })
    ];

	   };

	}
