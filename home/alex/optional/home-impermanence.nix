{ inputs, lib, config, pkgs, outputs, ... }:  {
  home = {
    persistence = {
      "/persist/home/alex" = {
        directories = [
          "Documents"
          "Downloads"
          "Repositories"
          ".local/bin"
          ".local/state"
          ".local/share/nix"
          ".ssh"
          ".config"
        ];
        files = [
          ".bash_history"
        ];
        allowOther = true;
      };
    };
  };
}