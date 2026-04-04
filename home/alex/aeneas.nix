{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      #./optional/gnome-customizations.nix
      ./optional/cosmic-customizations.nix
      ./optional/desktop-packages.nix
      ./optional/security-tooling.nix
      ./optional/terminator.nix
      ./optional/zsh.nix
      ./optional/flameshot-gui.nix
      #./optional/hyprland
      ./optional/nvim
      ./optional/cava.nix
    ];

    cosmic-customizations.enable = true;
    desktop-packages.enable = true;
    security-tooling.enable = true;
    terminator.enable = true;
    zsh.enable = true;
    flameshot-gui.enable = true;
    nvim.enable = true;
    cava.enable = true;

}
