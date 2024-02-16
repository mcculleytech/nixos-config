{ inputs, lib, config, pkgs, outputs, ... }: {
  imports = [
    ./git.nix
    ./vim.nix
    ./home-impermanence.nix
  ];

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
