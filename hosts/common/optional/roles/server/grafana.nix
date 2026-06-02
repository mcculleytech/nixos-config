{ config, lib, ... }:
let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json);
in
{

  options = {
    grafana.enable =
      lib.mkEnableOption "enables Grafana dashboard";
  };

  config = lib.mkIf config.grafana.enable {

    # Sops secret for the session-signing key. Generate a value with
    # `head -c 32 /dev/urandom | base64 | tr -d '/+=' | head -c 32`
    # and add it to atreides's secrets.yaml under `grafana_secret_key`.
    sops.secrets.grafana_secret_key = {
      sopsFile = ../../../../../hosts/atreides/secrets.yaml;
      owner = "grafana";
      group = "grafana";
      mode = "0400";
    };

    # Grafana Dashboards (import by ID):
    # Node Exporter Full (1860): https://grafana.com/grafana/dashboards/1860
    # Blocky (13768): https://grafana.com/grafana/dashboards/13768
    # Traefik (17346): https://grafana.com/grafana/dashboards/17346
    services.grafana = {
      enable = true;
      settings = {
        server = {
          http_addr = "0.0.0.0";
          http_port = 3000;
          domain = "grafana.${tr_secrets.traefik.homelab_domain}";
          root_url = "https://grafana.${tr_secrets.traefik.homelab_domain}";
        };
        security = {
          # Grafana removed its built-in default secret_key in the
          # nixpkgs bump that landed via PR #96; option must be set
          # explicitly. Read from sops at runtime via Grafana's
          # $__file{} indirection — secret is declared below.
          "secret_key$__file" = config.sops.secrets.grafana_secret_key.path;
        };
      };
      provision = {
        datasources.settings = {
          # Old Prometheus rows pre-date the file-provisioned config and
          # have auto-generated UIDs that can't be mutated in place. Drop
          # them so the entries below recreate cleanly with stable UIDs
          # that the dashboards reference.
          deleteDatasources = [
            { name = "Prometheus"; orgId = 1; }
            { name = "prometheus-1"; orgId = 1; }
          ];
          datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            uid = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
          {
            name = "Loki";
            type = "loki";
            uid = "loki";
            url = "http://localhost:3100";
          }
          {
            name = "Tempo";
            type = "tempo";
            uid = "tempo";
            url = "http://localhost:3200";
            # Drill from a trace span into Loki logs sharing the same
            # service.name. tracesToMetrics + serviceMap intentionally
            # omitted — they require explicit queries / span_metrics and
            # would otherwise fail provisioning at startup.
            jsonData = {
              tracesToLogsV2 = {
                datasourceUid = "loki";
                tags = [ { key = "service.name"; value = "service_name"; } ];
                filterByTraceID = false;
              };
            };
          }
          ];
        };
        dashboards.settings = {
          apiVersion = 1;
          providers = [
            {
              name = "homelab";
              type = "file";
              options.path = ../../../../../dashboards;
            }
          ];
        };
      };
    };

    networking.firewall.allowedTCPPorts = [ 3000 ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/grafana"; user = "grafana"; group = "grafana"; }
        ];
      };
    };
  };

}
