{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      ./optional/gnome-customizations.nix
      ./optional/desktop-packages.nix
      ./optional/terminator.nix
      ./optional/zsh.nix
      ./optional/security-tooling.nix
      ./optional/flameshot-gui.nix
      ./optional/cava.nix
    ];

    gnome-customizations.enable = true;
    desktop-packages.enable = true;
    terminator.enable = true;
    zsh.enable = true;
    security-tooling.enable = true;
    flameshot-gui.enable = true;
    cava.enable = true;

}
