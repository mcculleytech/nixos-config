{ inputs, lib, config, pkgs, outputs, ... }:  {
  home = {
    persistence = {
      "/persist/home/alex" = {
        directories = [
          "Documents"
          "Downloads"
          "Pictures"
          "Videos"
          "Repositories"
          ".local/bin"
          ".local/share/nix"
        ];
        allowOther = true;
      };
    };
  };
}