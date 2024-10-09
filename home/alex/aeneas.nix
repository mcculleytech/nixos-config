{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      ./optional/gnome-customizations.nix
      ./optional/desktop-packages.nix
      ./optional/terminator.nix
      ./optional/zsh.nix
      ./optional/hyprland
      ./optional/nvim
    ];

}
