{ config, lib, ... }:
let
  hosts = config.lab.hosts;
in
{

  options = {
    prometheus-server.enable =
      lib.mkEnableOption "enables Prometheus monitoring server";
  };

  config = lib.mkIf config.prometheus-server.enable {

    services.prometheus = {
      enable = true;
      port = 9090;
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
