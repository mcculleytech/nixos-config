{ config, lib, pkgs, ... }:
let
  hosts = config.lab.hosts;

  images = {
    app   = "docker.io/syslifters/sysreptor:latest";
    db    = "docker.io/library/postgres:14-alpine";
    redis = "docker.io/library/redis:8.0-alpine";
  };

  onNet = alias: [ "--network=sysreptor" "--network-alias=${alias}" ];
  units = [ "podman-sysreptor-app.service" "podman-sysreptor-db.service" "podman-sysreptor-redis.service" ];

  ph = config.sops.placeholder;
  envFile = config.sops.templates."sysreptor.env".path;

  # Only Traefik on atreides may reach the app port (:8095).
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

    sops.templates."sysreptor.env" = {
      content = ''
        SECRET_KEY=${ph.sysreptor_secret_key}
        ENCRYPTION_KEYS=${ph.sysreptor_encryption_keys}
        DEFAULT_ENCRYPTION_KEY_ID=primary
        POSTGRES_DB=sysreptor
        POSTGRES_USER=sysreptor
        POSTGRES_PASSWORD=${ph.sysreptor_db_password}
        POSTGRES_HOST=db
        POSTGRES_PORT=5432
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
        };
        environmentFiles = [ envFile ];
        volumes = [
          "/persist/var/lib/sysreptor/db:/var/lib/postgresql/data"
        ];
        extraOptions = onNet "db";
      };

      sysreptor-redis = {
        image = images.redis;
        cmd = [ "sh" "-c" "exec redis-server --requirepass \"$REDIS_PASSWORD\"" ];
        environmentFiles = [ envFile ];
        volumes = [
          "/persist/var/lib/sysreptor/redis:/data"
        ];
        extraOptions = onNet "redis";
      };

      sysreptor-app = {
        image = images.app;
        ports = [ "8095:8000" ];
        dependsOn = [ "sysreptor-db" "sysreptor-redis" ];
        environmentFiles = [ envFile ];
        environment = {
          ALLOWED_HOSTS = "sysreptor.${config.lab.homelabDomain},localhost,127.0.0.1,${hosts.saruman.ip}";
          USE_X_FORWARDED_HOST = "true";
          USE_X_FORWARDED_PORT = "true";
          SECURE_SSL_REDIRECT = "true";
          SECURE_PROXY_SSL_HEADER = "HTTP_X_FORWARDED_PROTO,https";
        };
        volumes = [
          "/persist/var/lib/sysreptor/data:/data"
        ];
        extraOptions = onNet "app";
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
