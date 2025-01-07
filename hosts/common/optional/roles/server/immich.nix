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
        mediaLocation = "/var/lib/immich/media";
        user = "immich";
        group = "immich";
        environment = {
                  REDIS_HOSTNAME = "immich_redis";
        };
    };

    environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
          "/var/lib/postgresql"
          "/var/lib/redis-immich"
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
        what = "10.1.8.4:/mnt/billthepony/immich";
        where = "/var/lib/immich/media";
      })
      (commonMountOptions // {
        what = "10.1.8.4:/mnt/billthepony/pictures";
        where = "/mnt/nfs-photos";
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
      (commonAutoMountOptions // { where = "/var/lib/immich/media"; })
      (commonAutoMountOptions // { where = "/mnt/nfs-photos"; })
    ];

     };

  }
