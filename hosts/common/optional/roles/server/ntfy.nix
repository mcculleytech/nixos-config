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

    # DynamicUser requires /var/lib/private with mode 0700
    systemd.tmpfiles.rules = [
      "d /var/lib/private 0700 root root -"
    ];

    # DynamicUser uses /var/lib/private; persist that path for impermanence
    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/private/ntfy-sh"; user = "root"; group = "root"; mode = "0700"; }
        ];
      };
    };
  };
}
