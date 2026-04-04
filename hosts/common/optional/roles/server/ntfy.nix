{ config, lib, ... }:
let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json);
in
{
  options = {
    ntfy.enable = lib.mkEnableOption "enables ntfy push notification server";
  };

  config = lib.mkIf config.ntfy.enable {

    services.ntfy-sh = {
      enable = true;
      settings = {
        base-url = "https://ntfy.${tr_secrets.traefik.homelab_domain}";
        listen-http = ":2586";
        behind-proxy = true;
      };
    };

    networking.firewall.allowedTCPPorts = [ 2586 ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/ntfy-sh"; user = "ntfy-sh"; group = "ntfy-sh"; }
        ];
      };
    };
  };
}
