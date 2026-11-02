{ config, lib, pkgs, ... }:
let
  hosts = config.lab.hosts;

  # Upstream stopped versioned API tags at 2.11.209 (Aug 2026); playwright and
  # nuq-postgres only publish `latest`. Pin all three by digest and bump them
  # TOGETHER — nuq-postgres's queue schema moves in lockstep with the API.
  # Pinned 2026-10-28.
  images = {
    api         = "ghcr.io/firecrawl/firecrawl@sha256:5af0243eb3b5d69671faf1ddf856c506fdea3600d84ab908d8d1d6a6f9dc0e64";
    playwright  = "ghcr.io/firecrawl/playwright-service@sha256:637fb8c8399634b02c2179da72566ce11644435e5d93e895bdbde4b1f9b0882a";
    nuqPostgres = "ghcr.io/firecrawl/nuq-postgres@sha256:d719b36160eac2fcbe16dc7e7360ddb9c82c40ea5da183d07bf4a755c6a0b2ae";
    redis       = "docker.io/library/redis:7.4-alpine";
    rabbitmq    = "docker.io/library/rabbitmq:3.13";
  };

  # Each container joins a private podman network under the hostname upstream's
  # compose uses, so the API's service URLs match upstream verbatim.
  onNet = alias: [ "--network=firecrawl" "--network-alias=${alias}" ];
  units = map (n: "podman-firecrawl-${n}.service")
    [ "api" "playwright" "redis" "rabbitmq" "nuq-postgres" ];

  ph = config.sops.placeholder;
  envFile = name: config.sops.templates."firecrawl-${name}.env".path;

  # Podman publishes ports via DNAT in nat PREROUTING, so the traffic never
  # hits nixos-fw (INPUT) and allowedTCPPorts can't restrict it. Filter in the
  # raw table instead: only Traefik on atreides may reach the unauthenticated
  # API — anyone else could use it as an SSRF proxy into the lab. dst-type
  # LOCAL leaves container-to-container traffic on the bridge alone.
  # `sfx` is appended to each line (e.g. "|| true" so -D tolerates a missing rule).
  dropRule = op: sfx: ''
    iptables -t raw ${op} PREROUTING -p tcp --dport 3002 -m addrtype --dst-type LOCAL ! -s ${hosts.atreides.ip} -j DROP ${sfx}
    ip6tables -t raw ${op} PREROUTING -p tcp --dport 3002 -m addrtype --dst-type LOCAL -j DROP ${sfx}
  '';
in {

  options = {
    firecrawl.enable =
      lib.mkEnableOption "enables self-hosted Firecrawl (scrape/crawl API)";
  };

  config = lib.mkIf config.firecrawl.enable {

    sops.secrets = lib.genAttrs
      [ "firecrawl_postgres_password" "firecrawl_redis_password" "firecrawl_rabbitmq_password" ]
      (_: { sopsFile = ../../../../saruman/secrets.yaml; });

    sops.templates = {
      "firecrawl-api.env" = {
        content = ''
          POSTGRES_PASSWORD=${ph.firecrawl_postgres_password}
          REDIS_URL=redis://:${ph.firecrawl_redis_password}@redis:6379
          REDIS_RATE_LIMIT_URL=redis://:${ph.firecrawl_redis_password}@redis:6379
          NUQ_RABBITMQ_URL=amqp://firecrawl:${ph.firecrawl_rabbitmq_password}@rabbitmq:5672
        '';
        restartUnits = [ "podman-firecrawl-api.service" ];
      };
      "firecrawl-nuq-postgres.env" = {
        content = "POSTGRES_PASSWORD=${ph.firecrawl_postgres_password}\n";
        restartUnits = [ "podman-firecrawl-nuq-postgres.service" ];
      };
      "firecrawl-redis.env" = {
        content = "REDIS_PASSWORD=${ph.firecrawl_redis_password}\n";
        restartUnits = [ "podman-firecrawl-redis.service" ];
      };
      "firecrawl-rabbitmq.env" = {
        content = ''
          RABBITMQ_DEFAULT_USER=firecrawl
          RABBITMQ_DEFAULT_PASS=${ph.firecrawl_rabbitmq_password}
        '';
        restartUnits = [ "podman-firecrawl-rabbitmq.service" ];
      };
    };

    systemd.services.podman-network-firecrawl = {
      description = "Create the firecrawl podman network";
      requiredBy = units;
      before = units;
      path = [ pkgs.podman ];
      serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
      script = "podman network exists firecrawl || podman network create firecrawl";
    };

    virtualisation.oci-containers.containers = {

      # Only :3002 is published to the host, and only atreides may reach it
      # (see dropRule). Redis, RabbitMQ, Postgres and Playwright stay on the
      # private network. The API itself is unauthenticated
      # (USE_DB_AUTHENTICATION=false); backing-service creds come from sops.
      firecrawl-api = {
        image = images.api;
        ports = [ "3002:3002" ];
        dependsOn = [ "firecrawl-redis" "firecrawl-rabbitmq" "firecrawl-nuq-postgres" "firecrawl-playwright" ];
        # No health gating in oci-containers: if the API starts before
        # RabbitMQ/Postgres are ready it exits and systemd restarts it.
        environmentFiles = [ (envFile "api") ];
        environment = {
          HOST = "0.0.0.0";
          PORT = "3002";
          ENV = "local";
          USE_DB_AUTHENTICATION = "false";
          PLAYWRIGHT_MICROSERVICE_URL = "http://playwright-service:3000/scrape";
          # Queue DB is private to the podman network.
          POSTGRES_HOST = "nuq-postgres";
          POSTGRES_PORT = "5432";
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "postgres";
          EXTRACT_WORKER_PORT = "3004";
          WORKER_PORT = "3005";
          HARNESS_STARTUP_TIMEOUT_MS = "60000";
          NUM_WORKERS_PER_QUEUE = "8";
          CRAWL_CONCURRENT_REQUESTS = "10";
          MAX_CONCURRENT_JOBS = "5";
          BROWSER_POOL_SIZE = "5";
          LOGGING_LEVEL = "INFO";
        };
        extraOptions = onNet "api" ++ [
          "--memory=8g" "--memory-swap=8g" "--cpus=4"
          "--ulimit=nofile=65535:65535"
        ];
      };

      # Chromium leaks/hangs under long crawls — hard memory cap so it gets
      # OOM-killed and restarted instead of eating saruman.
      firecrawl-playwright = {
        image = images.playwright;
        environment = {
          PORT = "3000";
          MAX_CONCURRENT_PAGES = "10";
        };
        extraOptions = onNet "playwright-service" ++ [
          "--memory=4g" "--memory-swap=4g" "--cpus=2"
          "--security-opt=no-new-privileges"
          "--cap-drop=ALL"
          "--tmpfs=/tmp/.cache:noexec,nosuid,size=1g"
        ];
      };

      firecrawl-redis = {
        image = images.redis;
        environmentFiles = [ (envFile "redis") ];
        # Expanded by sh inside the container (cmd is single-quoted on the host).
        cmd = [ "sh" "-c" "exec redis-server --bind 0.0.0.0 --requirepass \"$REDIS_PASSWORD\"" ];
        extraOptions = onNet "redis";
      };

      firecrawl-rabbitmq = {
        image = images.rabbitmq;
        environmentFiles = [ (envFile "rabbitmq") ];
        extraOptions = onNet "rabbitmq";
      };

      # No volume on purpose: upstream treats this as a transient job queue,
      # so the image's VOLUME is an anonymous volume discarded with the
      # container (--rm). Nothing to chown — avoids the speaches :U/tmpfiles
      # fight entirely. Cost: in-flight jobs are lost on restart. Because the
      # DB is recreated each start, a rotated password applies on restart.
      firecrawl-nuq-postgres = {
        image = images.nuqPostgres;
        environmentFiles = [ (envFile "nuq-postgres") ];
        environment = {
          POSTGRES_USER = "postgres";
          POSTGRES_DB = "postgres";
        };
        extraOptions = onNet "nuq-postgres";
      };
    };

    networking.firewall.extraCommands = ''
      ${dropRule "-D" "2>/dev/null || true"}
      ${dropRule "-A" ""}
    '';
    networking.firewall.extraStopCommands = dropRule "-D" "2>/dev/null || true";
  };
}
