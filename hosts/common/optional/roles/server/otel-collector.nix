{ config, lib, pkgs, ... }:
{
  options = {
    otel-collector.enable = lib.mkEnableOption "enables OpenTelemetry Collector (contrib distro)";
  };

  config = lib.mkIf config.otel-collector.enable {

    services.opentelemetry-collector = {
      enable = true;
      # The "core" otelcol distro lacks the `loki` and `deltatocumulative`
      # processors/exporters we need. Contrib includes them.
      package = pkgs.opentelemetry-collector-contrib;

      settings = {
        receivers = {
          otlp = {
            protocols = {
              # HTTP only — gRPC behind Traefik needs h2c plumbing we don't
              # want to manage. Bind to all interfaces so workstations on
              # the lab subnet can ship directly, and so Traefik's reverse
              # proxy can also reach it.
              http = {
                endpoint = "0.0.0.0:4318";
              };
            };
          };
        };

        processors = {
          batch = {
            timeout = "5s";
            send_batch_size = 1024;
          };

          # Claude Code (and most OTel SDKs) export metrics with delta
          # temporality by default. Prometheus expects cumulative. The
          # client also sets OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE=cumulative,
          # but this processor is the durable backstop — converts any
          # delta sums/histograms that slip through before they reach
          # Prometheus's OTLP receiver.
          "deltatocumulative" = {
            max_streams = 50000;
            max_stale = "5m";
          };

          resource = {
            attributes = [
              { key = "deployment.environment"; value = "homelab"; action = "upsert"; }
            ];
          };
        };

        exporters = {
          # Prometheus 3.x native OTLP receiver — no remote-write needed.
          "otlphttp/prom" = {
            endpoint = "http://localhost:9090/api/v1/otlp";
            tls.insecure = true;
          };

          # The dedicated `loki` exporter was removed from otelcol-contrib in
          # 0.151.0. Push logs to Loki's native OTLP endpoint instead (Loki
          # ≥3.x serves /otlp/v1/logs; otlphttp appends /v1/logs to the
          # endpoint). allow_structured_metadata is already enabled in loki.nix.
          "otlphttp/loki" = {
            endpoint = "http://localhost:3100/otlp";
            tls.insecure = true;
          };

          "otlp/tempo" = {
            endpoint = "localhost:4319";
            tls.insecure = true;
          };
        };

        service = {
          telemetry = {
            metrics = {
              # Expose collector self-metrics on :8888 for Prometheus.
              readers = [
                {
                  pull.exporter.prometheus = {
                    host = "0.0.0.0";
                    port = 8888;
                  };
                }
              ];
            };
            logs.level = "warn";
          };

          pipelines = {
            metrics = {
              receivers = [ "otlp" ];
              processors = [ "batch" "deltatocumulative" "resource" ];
              exporters = [ "otlphttp/prom" ];
            };
            logs = {
              receivers = [ "otlp" ];
              processors = [ "batch" "resource" ];
              exporters = [ "otlphttp/loki" ];
            };
            traces = {
              receivers = [ "otlp" ];
              processors = [ "batch" "resource" ];
              exporters = [ "otlp/tempo" ];
            };
          };
        };
      };
    };

    # 4318 is the OTLP/HTTP receiver. 8888 is collector self-telemetry
    # scraped by Prometheus. Bound on the lab subnet only would be tighter
    # but the rest of the homelab stack uses host-wide opens — match that.
    networking.firewall.allowedTCPPorts = [ 4318 8888 ];

    # Collector runs as a DynamicUser; state goes under /var/lib/private.
    # Persist that so deltatocumulative's in-memory streams survive a
    # reboot's tmpfs root wipe. (The processor itself is in-memory only,
    # but the bind-mount needs an existing source.)
    systemd.tmpfiles.rules = [
      "d /var/lib/private 0700 root root -"
    ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/private/opentelemetry-collector"; user = "root"; group = "root"; mode = "0700"; }
        ];
      };
    };
  };
}
