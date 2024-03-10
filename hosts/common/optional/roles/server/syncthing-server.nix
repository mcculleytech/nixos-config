{ inputs, config, lib, ... }: {

  sops.secrets = {
    syncthing_svr_id = {
      sopsFile = ../../../secrets/main.yaml;
    };
    syncthing_svr_user = {
      sopsFile = ../../../secrets/main.yaml;
    };
    syncthing_svr_pass = {
      sopsFile = ../../../secrets/main.yaml;
    };
  };
  sops.templates = {
    "syncthing_svr_id".content = ''
      "${config.sops.placeholder.syncthing_svr_id}"
    '';
    "syncthing_svr_user".content = ''
      "${config.sops.placeholder.syncthing_svr_user}"
    '';
    "syncthing_svr_pass".content = ''
      "${config.sops.placeholder.syncthing_svr_pass}"
    '';
  };

  environment.persistence = {
    "/persist" = {
    hideMounts = true;
      directories = [
        "/var/lib/syncthing"
      ];
    };
  };

  services = {
    syncthing = {
      enable = true;
      openDefaultPorts = true;
      # Uncomment this line and firewall line for gui access.
      guiAddress = "0.0.0.0:8384";
      settings = {
        folders = {
          "Obsidian" = {
            path = "/var/lib/syncthing/Obsidian";

          };
          "Synced-Documents" = {
            path = "/var/lib/syncthing/Synced-Documents";

          };
          "Pixel-Photos" = {
            path = "/var/lib/syncthing/Pixel-Photos";

          };
        };
        gui = {
          user = "${config.sops.placeholder.syncthing_svr_user}";
          password = "${config.sops.placeholder.syncthing_svr_pass}";
        };
      };
    };
  };
  # Allow gui 
  networking.firewall.allowedTCPPorts = [ 8384 ];
}