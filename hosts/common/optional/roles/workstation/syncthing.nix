{ config, pkgs, lib, ... }:
let
  st_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_syncthing.json);
in
{

  options = {
    syncthing-workstation.enable = lib.mkEnableOption "enables syncthing workstation client";
  };

  config = lib.mkIf config.syncthing-workstation.enable {
    services = {
      syncthing = {
        package = pkgs.syncthing;
        enable = true;
        openDefaultPorts = true;
        user = "alex";
        configDir = "/home/alex/.config/syncthing";
        settings = {
          devices = {
            "phantom" = {
              id = "${st_secrets.syncthing.phantom_id}";
              autoAcceptFolders = true;
            };
          };
          folders = {
            "Synced-Documents" = {
              id = "Synced-Documents";
              path = "~/Documents/Synced-Documents";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "phantom"
              ];
            };
            "Pixel-Photos" = {
              id = "pixel_7_pro_rhez-photos";
              path = "~/Pictures/Pixel-Photos";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "phantom"
              ];
            };
          };
        };
      };
    };
  };
}
