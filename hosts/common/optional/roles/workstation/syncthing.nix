{config, pkgs, ... }:
let 
  st_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_syncthing.json);
in
{
  services = {
    syncthing = {
      package = pkgs.unstable.syncthing;
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
          "Obsidian" = {
            id = "Obsidian";
            path = "~/Documents/Obsidian";
            devices = [
              "phantom"
            ];
          };
          "Synced-Documents" = {
            id = "Synced-Documents";
            path = "~/Documents/Synced-Documents";
            devices = [
              "phantom"
            ];
          };
          "Pixel-Photos" = {
            id = "Pixel-Photos";
            path = "~/Pictures/Pixel-Photos";
            devices = [
              "phantom"
            ];
          };
        };
      };
      overrideFolders = true;
    };
  };
}