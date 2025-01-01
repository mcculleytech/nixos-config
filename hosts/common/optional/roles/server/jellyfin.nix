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
	};


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
	      what = "10.1.8.4:/mnt/billthepony/movies";
	      where = "/var/lib/jellyfin/movies";
	    })
	    (commonMountOptions // {
	      what = "10.1.8.4:/mnt/billthepony/tv-shows";
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