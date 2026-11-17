{ config, lib, pkgs, ... }:
let
  hosts = config.lab.hosts;

  # Pinned by digest, not tag — the same house standard as firecrawl.nix: an
  # unattended `podman pull` must not change the running version under a live
  # project, and `latest` on the app image certainly would.
  #
  #   syslifters/sysreptor  :latest     → app version VERSION=2026.102 (from the image Env)
  #   library/postgres      :14-alpine  → upstream's own compose default
  #   library/redis         :8.0-alpine
  # Pinned 2026-11-17. Bump the app and the Postgres image TOGETHER, and treat a
  # Postgres major-version change as a planned migration — dump, pg_upgrade,
  # verify — never as an image tag change: the datadir is version-specific and a
  # new major against an old datadir either refuses to start or, worse, comes up
  # on an empty one beside it.
  images = {
    app   = "docker.io/syslifters/sysreptor@sha256:bddb1b6e1e58ae8462a88fb6d10c24814989804b6e2b9d170b4f1cb69bfdf7e6";
    db    = "docker.io/library/postgres@sha256:e7d9e6aac7fe3232f7661da103aebc0ce38b04105b46af5e9edd5ef6bc343f20";
    redis = "docker.io/library/redis@sha256:5f61955be8ab2ccee9372b84ae4d4da2e2b156f87281e3f218544055e7ee04d4";
  };

  onNet = alias: [ "--network=sysreptor" "--network-alias=${alias}" ];
  units = [ "podman-sysreptor-app.service" "podman-sysreptor-db.service" "podman-sysreptor-redis.service" ];

  ph = config.sops.placeholder;
  envFile = config.sops.templates."sysreptor.env".path;

  # Podman publishes ports via DNAT in nat PREROUTING, so traffic never reaches
  # nixos-fw (INPUT) and allowedTCPPorts cannot restrict it. SysReptor has its own
  # login, but it has no business being reachable from the LAN, so filter in the
  # raw table: only Traefik on atreides may reach :8095. dst-type LOCAL leaves
  # container-to-container traffic on the bridge alone. Same trick as firecrawl.
  dropRule = op: sfx: ''
    iptables -t raw ${op} PREROUTING -p tcp --dport 8095 -m addrtype --dst-type LOCAL ! -s ${hosts.atreides.ip} -j DROP ${sfx}
    ip6tables -t raw ${op} PREROUTING -p tcp --dport 8095 -m addrtype --dst-type LOCAL -j DROP ${sfx}
  '';
in {

  options = {
    sysreptor.enable =
      lib.mkEnableOption "enables self-hosted SysReptor pentest reporting platform";
  };

  config = lib.mkIf config.sysreptor.enable {

    sops.secrets = lib.genAttrs
      [
        "sysreptor_secret_key"
        "sysreptor_encryption_keys"
        "sysreptor_db_password"
        "sysreptor_redis_password"
      ]
      (_: { sopsFile = ../../../../saruman/secrets.yaml; });

    # Name note, verified against upstream: the *db* container takes
    # POSTGRES_{DB,USER,PASSWORD}; the *app* container takes
    # DATABASE_{HOST,PORT,NAME,USER,PASSWORD} (api/src/sysreptor/conf/settings.py —
    # DATABASE_HOST defaults to the empty string, so the app cannot connect at all
    # if only POSTGRES_* is set). Both sets live in this one file; each container
    # ignores the other's.
    #
    # ENCRYPTION_KEYS is parsed as a JSON list, not a bare string, so the sops
    # value must be the entire array, e.g.
    #   [{"id":"primary","key":"<32-byte base64>","cipher":"AES-GCM","revoked":false}]
    # matching DEFAULT_ENCRYPTION_KEY_ID.
    sops.templates."sysreptor.env" = {
      content = ''
        SECRET_KEY=${ph.sysreptor_secret_key}
        ENCRYPTION_KEYS=${ph.sysreptor_encryption_keys}
        DEFAULT_ENCRYPTION_KEY_ID=primary

        POSTGRES_DB=sysreptor
        POSTGRES_USER=sysreptor
        POSTGRES_PASSWORD=${ph.sysreptor_db_password}

        DATABASE_HOST=db
        DATABASE_PORT=5432
        DATABASE_NAME=sysreptor
        DATABASE_USER=sysreptor
        DATABASE_PASSWORD=${ph.sysreptor_db_password}

        REDIS_PASSWORD=${ph.sysreptor_redis_password}
        REDIS_URL=redis://:${ph.sysreptor_redis_password}@redis:6379/0
      '';
      restartUnits = [ "podman-sysreptor-app.service" ];
    };

    systemd.services.podman-network-sysreptor = {
      description = "Create the sysreptor podman network";
      requiredBy = units;
      before = units;
      path = [ pkgs.podman ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = "podman network exists sysreptor || podman network create sysreptor";
    };

    virtualisation.oci-containers.containers = {

      sysreptor-db = {
        image = images.db;
        environment = {
          POSTGRES_DB = "sysreptor";
          POSTGRES_USER = "sysreptor";
          # Upstream sets PGDATA=/data and mounts the volume there; the alpine
          # image's own default is /var/lib/postgresql/data. Match upstream, or a
          # later image bump can initialise a second, empty datadir.
          PGDATA = "/data";
        };
        environmentFiles = [ envFile ];
        volumes = [ "/persist/var/lib/sysreptor/db:/data" ];
        extraOptions = onNet "db";
      };

      sysreptor-redis = {
        image = images.redis;
        cmd = [ "sh" "-c" "exec redis-server --requirepass \"$REDIS_PASSWORD\"" ];
        environmentFiles = [ envFile ];
        volumes = [ "/persist/var/lib/sysreptor/redis:/data" ];
        extraOptions = onNet "redis";
      };

      sysreptor-app = {
        image = images.app;
        ports = [ "8095:8000" ];
        dependsOn = [ "sysreptor-db" "sysreptor-redis" ];
        environmentFiles = [ envFile ];
        environment = {
          # Django appends localhost/127.0.0.1/[::1] itself and derives
          # CSRF_TRUSTED_ORIGINS plus MFA_FIDO2_RP_ID from a single-host value.
          ALLOWED_HOSTS = "sysreptor.${config.lab.homelabDomain}";
          # SECURE_PROXY_SSL_HEADER is hardcoded upstream — not an env var.
          USE_X_FORWARDED_HOST = "true";
          USE_X_FORWARDED_PORT = "true";
          SECURE_SSL_REDIRECT = "true";
          DEBUG = "off";
        };
        volumes = [ "/persist/var/lib/sysreptor/data:/data" ];
        # Upstream runs this with init: true — one container supervises gunicorn,
        # a taskiq worker and headless Chromium.
        extraOptions = [ "--init" ] ++ onNet "app";
      };
    };

    systemd.tmpfiles.rules = [
      "d /persist/var/lib/sysreptor/db 0700 70 70 -"
      "d /persist/var/lib/sysreptor/redis 0700 999 999 -"
      "d /persist/var/lib/sysreptor/data 0700 1000 1000 -"
    ];

    networking.firewall.extraCommands = dropRule "-I" "";
    networking.firewall.extraStopCommands = dropRule "-D" "|| true";
  };
}
