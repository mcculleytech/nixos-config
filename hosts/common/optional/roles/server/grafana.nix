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
      };
      provision = {
        datasources.settings.datasources = [
          {
            name = "Prometheus";
            type = "prometheus";
            url = "http://localhost:9090";
            isDefault = true;
          }
        ];
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
