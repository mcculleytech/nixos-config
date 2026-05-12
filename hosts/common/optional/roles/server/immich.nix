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

    # tmpfiles for the local backup landing dir.
    systemd.tmpfiles.rules = [
      "d /persist/backups 0755 root root -"
      "d /persist/backups/postgres 0700 root root -"
      "d /persist/backups/postgres/immich 0700 root root -"
    ];

    # ─── Daily pg_dump of immich: local + NAS ──────────────────────────────
    # Two-destination backup. Photo/video blobs live on TrueNAS already (via
    # the NFS mount at /var/lib/immich/media), so this dump only covers the
    # postgres database — albums, faces, tags, sharing, EXIF index. Lose
    # this and the blobs survive but become an undifferentiated heap.
    #
    # Local /persist for fast restore; NAS for full-saruman-loss recovery.
    # Unit runs as root for the NAS write (NFS maproot UID 0 → 34); pg_dump
    # drops to postgres via runuser for peer-auth via PrivateTmp.
    systemd.services.immich-backup = {
      description = "Daily pg_dump of immich (local + NAS)";
      after = [ "postgresql.service" ];
      requires = [ "postgresql.service" ];
      unitConfig = lib.mkIf config.lab.nas-backups.enable {
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
        ReadWritePaths = [ "/persist/backups/postgres/immich" ]
          ++ lib.optional config.lab.nas-backups.enable config.lab.nas-backups.mountPath;
      };
      path = with pkgs; [ util-linux coreutils findutils config.services.postgresql.package ];
      script = ''
        set -eu
        ts=$(date -u +%Y-%m-%d)
        local_dst=/persist/backups/postgres/immich

        # pg_dump as postgres (peer-auth) into PrivateTmp.
        tmpfile=/tmp/immich-pg-$ts.dump.tmp
        runuser -u postgres -- pg_dump --format=custom --file="$tmpfile" immich

        # Local destination — primary, always written.
        cp -f "$tmpfile" "$local_dst/immich-pg-$ts.dump"
        find "$local_dst" -name 'immich-pg-*.dump' -mtime +30 -delete

        ${lib.optionalString config.lab.nas-backups.enable ''
          # NAS mirror — NFS maproot translates UID 0 → backup on write.
          nas_dst=${config.lab.nas-backups.mountPath}/saruman/immich
          install -d -m 0750 -o backup -g backup "$nas_dst"
          cp -f "$tmpfile" "$nas_dst/immich-pg-$ts.dump"
          chown backup:backup "$nas_dst/immich-pg-$ts.dump" 2>/dev/null || true
          find "$nas_dst" -name 'immich-pg-*.dump' -mtime +30 -delete
        ''}

        rm -f "$tmpfile"
      '';
    };

    systemd.timers.immich-backup = {
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
