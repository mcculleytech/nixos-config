{

    imports = [
      ./global
      ./optional/gnome-customizations.nix
      ./optional/offsec-pkgs.nix
      ./optional/desktop-packages.nix
      ./optional/terminator.nix
      ./optional/zsh.nix
    ];

  nixpkgs = {
    overlays = [
    outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

  programs.zsh = {
    shellAliases= {
      os-rebuild   = "export HOSTNAME=$(hostname); sudo nixos-rebuild switch --flake '/home/alex/Repositories/nixos-config/#achilles'";
      home-rebuild = "export HOSTNAME=$(hostname); home-manager switch --flake '/home/alex/Repositories/nixos-config/#alex@achilles'";
    };
  };

}