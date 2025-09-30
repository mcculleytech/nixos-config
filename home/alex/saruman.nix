{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      ./optional/terminator.nix
      ./optional/zsh.nix
      ./optional/security-tooling.nix
    ];

  home.packages = with pkgs; 
  [
    bitwarden
    retroarchFull
    nixos-anywhere
    rpcs3
    game-devices-udev-rules
    firefox
    unstable.ollama
    unstable.xonotic
    # unstable.jellyfin-media-player
  ];

}
