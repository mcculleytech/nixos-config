{ pkgs, config, lib, ... }: {

  options = {
    n8n.enable =
      lib.mkEnableOption "enables n8n automation platform";
  };

  config = lib.mkIf config.n8n.enable {

    users.users.n8n = {
      isSystemUser = true;
      group = "n8n";
    };
    users.groups.n8n = {};

    services.n8n = {
      enable = true;
      openFirewall = true;
      environment = {
        N8N_HOST = "0.0.0.0";
        N8N_SECURE_COOKIE = "false";
        N8N_PROTOCOL = "https";
        WEBHOOK_URL = "https://n8n.${
          (builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json)).traefik.homelab_domain
        }";
      };
    };

    systemd.services.n8n.serviceConfig = {
      DynamicUser = lib.mkForce false;
      User = "n8n";
      Group = "n8n";
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/private/n8n 0750 n8n n8n -"
    ];

    environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
          "/var/lib/private/n8n"
        ];
      };
    };
  };

}
