{ inputs, lib, config, pkgs, outputs, ... }:  {
  home = {
    persistence = {
      "/persist/home/alex" = {
        directories = [
          "Documents"
          "Downloads"
          "Pictures"
          "Videos"
          ".local/bin"
          ".local/share/nix" # trusted settings and repl history
        ];
        allowOther = true;
      };
    };
  };
}