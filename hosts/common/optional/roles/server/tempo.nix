{ config, lib, ... }:
{
  options = {
    tempo.enable = lib.mkEnableOption "enables Tempo distributed tracing backend";
  };

  config = lib.mkIf config.tempo.enable {

    services.tempo = {
      enable = true;
      settings = {
        # Single-binary deployment; no clustering.
        target = "all";
        auth_enabled = false;

        # HTTP API (used by Grafana datasource + /metrics) on :3200,
        # gRPC ring/internal on :9095. OTLP gRPC receiver from the
        # collector on :4319 (4317 is reserved in case we later add a
        # direct OTLP gRPC path).
        server = {
          http_listen_address = "0.0.0.0";
          http_listen_port = 3200;
          grpc_listen_address = "0.0.0.0";
          grpc_listen_port = 9095;
          log_level = "warn";
        };

        distributor.receivers.otlp.protocols = {
          grpc.endpoint = "127.0.0.1:4319";
        };

        ingester = {
          max_block_duration = "5m";
          lifecycler.ring.replication_factor = 1;
        };

        compactor.compaction = {
          block_retention = "168h"; # 7 days
        };

        storage.trace = {
          backend = "local";
          wal.path = "/var/lib/tempo/wal";
          local.path = "/var/lib/tempo/blocks";
        };

        usage_report.reporting_enabled = false;
      };
    };

    # 3200 is Tempo's HTTP API (Grafana datasource queries land here, and
    # /metrics is scraped by Prometheus). Grafana on the same host reaches
    # Tempo via localhost so this only matters for off-host callers, but
    # match the loki/prometheus pattern — leaving it closed makes ad-hoc
    # curl debugging from a workstation hang on connect, which already
    # bit us once.
    networking.firewall.allowedTCPPorts = [ 3200 ];

    # Tempo's NixOS module runs as a DynamicUser, so actual state lives
    # under /var/lib/private/tempo (with /var/lib/tempo being a symlink).
    # Persist the private path with root:root 0700, mirroring ntfy.nix.
    systemd.tmpfiles.rules = [
      "d /var/lib/private 0700 root root -"
    ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/private/tempo"; user = "root"; group = "root"; mode = "0700"; }
        ];
      };
    };
  };
}
