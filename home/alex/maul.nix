{

    imports = [
      ./global
    ];

  programs.bash = {
    enable = true;
    shellAliases = {
      os-rebuild = "sudo nixos-rebuild switch --flake .#maul";
    };
  };

}