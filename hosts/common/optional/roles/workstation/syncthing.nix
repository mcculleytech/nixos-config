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
          "maul" = {
            id = "${st_secrets.syncthing.maul_id}";
            autoAcceptFolders = true;
          };
        };
        folders = {
          # "Obsidian" = {
          #   id = "Obsidian";
          #   path = "~/Documents/Obsidian";
          #   versioning = {
          #     type = "simple";
          #     params.keep = "5";
          #   };            
          #   devices = [
          #     "phantom"
          #   ];
          # };
          # "Logseq" = {
          #   id = "Logseq";
          #   path = "~/Documents/Logseq";
          #   versioning = {
          #     type = "simple";
          #     params.keep = "5";
          #   };            
          #   devices = [
          #     "phantom"
          #   ];
          # };
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
}