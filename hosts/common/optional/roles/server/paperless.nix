{ pkgs, config, lib, ... }: {

  options = {
    paperless.enable =
      lib.mkEnableOption "Paperless-ngx document management";
  };

  config = lib.mkIf config.paperless.enable {

    services.paperless = {
      enable = true;
      address = "0.0.0.0";
      port = 28981;
      passwordFile = config.sops.secrets."paperless/admin_password".path;
      database.createLocally = true;
      configureTika = true;
      settings = {
        PAPERLESS_OCR_LANGUAGE = "eng";
        PAPERLESS_ADMIN_USER = "admin";
        PAPERLESS_URL = "https://paperless.${
          (builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json)).traefik.homelab_domain
        }";
      };
    };

    sops.secrets."paperless/admin_password" = {
      sopsFile = ../../../../../secrets/paperless.yaml;
    };

    networking.firewall.allowedTCPPorts = [ 28981 ];

    # PostgreSQL persistence is handled in impermanence.nix
    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          {
            directory = "/var/lib/paperless";
            user = "paperless";
            group = "paperless";
          }
        ];
      };
    };
  };

}
