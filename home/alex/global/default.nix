{ inputs, lib, config, pkgs, outputs, ... }: {
  imports = [
    ./git.nix
    ./gnome-customizations.nix
    ./offsec-pkgs.nix
    ./packages.nix
    ./terminator.nix
    ./vim.nix
    ./zsh.nix
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

  home = {
    username = "alex";
    homeDirectory = "/home/alex";
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";
}