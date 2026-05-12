  { pkgs, lib, config, ... }:
  {

  options = {
    immich.enable =
      lib.mkEnableOption "enables immich server";
  };

  config = lib.mkIf config.immich.enable {

    services.immich = {
        enable = true;
        package = pkgs.unstable.immich;
        openFirewall = true;
        host = "0.0.0.0";
        mediaLocation = "/var/lib/immich/media";
        user = "immich";
        group = "immich";
        environment = {
                  REDIS_HOSTNAME = "immich_redis";
        };
    };

    # PostgreSQL persistence is handled in impermanence.nix
    environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
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
        what = "${config.lab.hosts.truenas.ip}:/mnt/billthepony/immich";
        where = "/var/lib/immich/media";
      })
      (commonMountOptions // {
        what = "${config.lab.hosts.truenas.ip}:/mnt/billthepony/pictures";
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

    # ─── Daily pg_dump of immich → NAS backup share ────────────────────────
    # Photo/video blobs live on TrueNAS already (via the NFS mount at
    # /var/lib/immich/media), so this backup only covers the postgres
    # database — albums, faces, tags, sharing, EXIF index. Lose this and
    # the blobs would survive but be an undifferentiated heap.
    #
    # Unit runs as root so NFS maproot=backup (UID 0 → 34) translates writes
    # cleanly into the NAS-side `backup` user's ownership. pg_dump itself
    # drops to postgres via runuser for peer-auth; that intermediate file
    # lives in PrivateTmp so it can't leak.
    systemd.services.immich-backup = lib.mkIf config.lab.nas-backups.enable {
      description = "Daily pg_dump of immich → NAS";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      unitConfig = {
        RequiresMountsFor = [ config.lab.nas-backups.mountPath ];
      };
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ config.lab.nas-backups.mountPath ];
      };
      path = with pkgs; [ util-linux coreutils findutils config.services.postgresql.package ];
      script = ''
        set -eu
        ts=$(date -u +%Y-%m-%d)
        dst=${config.lab.nas-backups.mountPath}/saruman/immich
        install -d -m 0750 -o backup -g backup "$dst"

        # pg_dump runs as postgres for peer-auth, writes into PrivateTmp.
        tmpfile=/tmp/immich-pg-$ts.dump.tmp
        runuser -u postgres -- pg_dump --format=custom --file="$tmpfile" immich

        # Move to NAS as root — NFS server maps UID 0 → backup (UID 34) via
        # the export's maproot setting, so the file lands with correct
        # NAS-side ownership. Explicit chown is belt-and-suspenders.
        mv "$tmpfile" "$dst/immich-pg-$ts.dump"
        chown backup:backup "$dst/immich-pg-$ts.dump"

        # Retention.
        find "$dst" -name 'immich-pg-*.dump' -mtime +30 -delete
      '';
    };

    systemd.timers.immich-backup = lib.mkIf config.lab.nas-backups.enable {
      description = "Daily timer for immich pg_dump → NAS";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        # 30min offset from agent-memory's 03:00 daily backup so the two
        # don't slam Postgres at the same instant.
        OnCalendar = "*-*-* 03:30:00";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };

     };

  }
