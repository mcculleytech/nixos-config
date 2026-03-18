{ pkgs, config, lib, ... }: {

  options = {
    miniflux.enable =
      lib.mkEnableOption "enables Miniflux RSS reader";
  };

  config = lib.mkIf config.miniflux.enable {

    services.miniflux = {
      enable = true;
      createDatabaseLocally = true;
      config = {
        LISTEN_ADDR = "0.0.0.0:8080";
        BASE_URL = "https://miniflux.${
          (builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json)).traefik.homelab_domain
        }";
      };
      adminCredentialsFile = config.sops.secrets."miniflux/admin_credentials".path;
    };

    sops.secrets."miniflux/admin_credentials" = {
      sopsFile = ../../../../../secrets/miniflux.yaml;
    };

    networking.firewall.allowedTCPPorts = [ 8080 ];

    # PostgreSQL persistence is handled in impermanence.nix
  };

}
