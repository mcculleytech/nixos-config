# This is your home-manager configuration file
# Use this to configure your home environment (it replaces ~/.config/nixpkgs/home.nix)

{ inputs, outputs, lib, config, pkgs, ... }: {
  # You can import other home-manager modules here
  imports = [
  # If you want to use home-manager modules from other flakes (such as nix-colors):
    # inputs.nix-colors.homeManagerModule

    # You can also split up your configuration and import pieces of it here:
    # ./nvim.nix
    ../../modules/home-manager/achilles.nix
  ];

  nixpkgs = {
    # You can add overlays here
    overlays = [
    # Does not work yet
    outputs.overlays.unstable-packages
    ];
    # Configure your nixpkgs instance
    config = {
      # Disable if you don't want unfree packages
      allowUnfree = true;
      # Workaround for https://github.com/nix-community/home-manager/issues/2942
      allowUnfreePredicate = (_: true);
      permittedInsecurePackages = [
        "openssl-1.1.1u"
      ];
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

  # Host specific aliases. Tried with variables and couldn't get it to work.
  programs.zsh = {
    shellAliases= {
      os-rebuild   = "export HOSTNAME=$(hostname); sudo nixos-rebuild switch --flake '/home/alex/Repositories/nixos-config/#achilles'";
      home-rebuild = "export HOSTNAME=$(hostname); home-manager switch --flake '/home/alex/Repositories/nixos-config/#alex@achilles'";
    };
  };

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.05";
}
