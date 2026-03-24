{ config, lib, ... }: {

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
                "10.1.8.129:9100" # atreides
                "10.1.8.121:9100" # phantom
                "10.1.8.6:9100"   # saruman
                "10.2.1.245:9100" # vader
              ];
            }
          ];
        }
        {
          job_name = "traefik";
          static_configs = [
            {
              targets = [ "10.1.8.129:8080" ];
            }
          ];
        }
        {
          job_name = "blocky";
          static_configs = [
            {
              targets = [
                "10.1.8.129:4000" # atreides
                "10.1.8.121:4000" # phantom
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
