{ config, lib, ... }:
let
  hosts = config.lab.hosts;
in
{
  # ─── Module structure ────────────────────────────────────────────────────
  # Split for navigability:
  #   • default.nix       — option declaration + core scrape configs
  #   • alertmanager.nix  — alertmanager service + ntfy webhook routing
  #   • alerts-<group>.nix — one file per logical alert group; each
  #                          contributes to services.prometheus.rules via
  #                          the NixOS module merge. To add a new alert
  #                          group: create alerts-foo.nix, declare its
  #                          rules, drop into imports below.
  imports = [
    ./alertmanager.nix
    ./alerts-disk.nix
  ];

  options = {
    prometheus-server.enable =
      lib.mkEnableOption "enables Prometheus monitoring server";
  };

  config = lib.mkIf config.prometheus-server.enable {

    services.prometheus = {
      enable = true;
      port = 9090;
      # --web.enable-otlp-receiver exposes /api/v1/otlp/v1/metrics, the
      # native OTLP HTTP ingest path. The otel-collector exporter pushes
      # Claude Code metrics here; removes the need for prometheusremotewrite.
      extraFlags = [ "--web.enable-otlp-receiver" ];
      globalConfig = {
        scrape_interval = "15s";
      };
      scrapeConfigs = [
        {
          job_name = "node";
          static_configs = [
            {
              targets = [
                "${hosts.atreides.ip}:9100"
                "${hosts.phantom.ip}:9100"
                "${hosts.saruman.ip}:9100"
                "${hosts.vader.ip}:9100"
              ];
            }
          ];
        }
        {
          job_name = "traefik";
          static_configs = [
            {
              targets = [ "${hosts.atreides.ip}:8080" ];
            }
          ];
        }
        {
          job_name = "blocky";
          static_configs = [
            {
              targets = [
                "${hosts.atreides.ip}:4000"
                "${hosts.phantom.ip}:4000"
              ];
            }
          ];
        }
        {
          # nvidia_gpu_exporter on every host with `nvidia.enable = true`
          # (wired in `hosts/common/optional/nvidia.nix`). Today that's
          # just saruman — Ollama + Immich ML + Jellyfin transcodes all
          # share one GPU there. Add new hosts to this static list when
          # the nvidia module fires up on them.
          job_name = "nvidia-gpu";
          static_configs = [
            {
              targets = [
                "${hosts.saruman.ip}:9835"
              ];
            }
          ];
        }
        {
          job_name = "otel-collector";
          static_configs = [
            { targets = [ "${hosts.atreides.ip}:8888" ]; }
          ];
        }
        {
          job_name = "loki";
          static_configs = [
            { targets = [ "${hosts.atreides.ip}:3100" ]; }
          ];
        }
        {
          job_name = "tempo";
          static_configs = [
            { targets = [ "${hosts.atreides.ip}:3200" ]; }
          ];
        }
      ];
    };

    networking.firewall.allowedTCPPorts = [ 9090 ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/prometheus2"; user = "prometheus"; group = "prometheus"; }
        ];
      };
    };
  };

}
