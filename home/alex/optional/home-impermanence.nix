{ inputs, lib, config, pkgs, outputs, ... }:  {
  home = {
    persistence = {
      "/persist/home/alex" = {
        directories = [
          "Documents"
          "Downloads"
          "Repositories"
          ".local/bin"
          ".local/share/nix"
          ".ssh"
          ".local"
          ".config"
          ".bash_history"
        ];
        allowOther = true;
      };
    };
  };
}