{ inputs, lib, config, pkgs, outputs, ... }: {
  imports = [
    ./git.nix
    ./vim.nix
  ];

  home = {
    username = "alex";
    homeDirectory = "/home/alex";
  };

  nixpkgs = {
    overlays = [
    outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
      permittedInsecurePackages = [
        "electron-27.3.11" # needed for logseq
      ];

    };
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";

}
