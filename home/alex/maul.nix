{

    imports = [
      ./global
      ./home-impermanace
    ];

  programs.bash = {
    enable = true;
    shellAliases = {
      os-rebuild = "sudo nixos-rebuild switch --flake .#maul";
    };
  };

}