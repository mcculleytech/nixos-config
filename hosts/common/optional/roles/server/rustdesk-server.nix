  { pkgs, lib, config, ... }:
  {

  options = {
    rustdesk-server.enable =
      lib.mkEnableOption "enables rustdesk server";
    };

    config = lib.mkIf config.rustdesk-server.enable {

      services.rustdesk-server = {  
        enable = true;
        openFirewall = true;
      };

    };

  }
