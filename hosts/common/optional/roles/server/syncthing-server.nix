{ inputs, config, lib, pkgs, ... }:
let 
  st_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_syncthing.json);
in 
{


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
      package = pkgs.unstable.syncthing;
      enable = true;
      user = "syncthing";
      openDefaultPorts = true;
      # Uncomment this line and firewall line for gui access.
      guiAddress = "0.0.0.0:8384";
      settings = {
        folders = {
          "Obsidian" = {
            id = "Obsidian";
            path = "/var/lib/syncthing/Obsidian";
            devices = [
              "achilles"
            ];
          };
          "Synced-Documents" = {
            id = "Synced-Documents";
            path = "/var/lib/syncthing/Synced-Documents";
            devices = [
              "achilles"
            ];
          };
          "Pixel-Photos" = {
            id = "Pixel-Photos";
            path = "/var/lib/syncthing/Pixel-Photos";
            devices = [
              "achilles"
            ];
          };
        };
        devices = {
          "achilles" = {
            id = "${st_secrets.syncthing.achilles_id}";
          };
          "aeneas" = {
            id = "${st_secrets.syncthing.aeneas_id}";
          };
          "pixel" = {
            id = "${st_secrets.syncthing.pixel_id}";
          };
          "TrueNAS" = {
            id = "${st_secrets.syncthing.truenas_id}";
          };
        };
        gui = {
          user = "${st_secrets.syncthing.phantom_user}";
          password = "${st_secrets.syncthing.phantom_pass}";
        };
        options = {
          localAnnounceEnabled = true;
          relaysEnabled = true;
          globalAnnounceEnabled = true;
        };
      };
      overrideFolders = true;
      overrideDevices = true;
    };
  };
  # FW Ports
  networking.firewall.allowedTCPPorts = [ 8384 22000 ];
  networking.firewall.allowedUDPPorts = [ 22000 21027 ];
}