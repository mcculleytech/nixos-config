{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      ./optional/terminator.nix
      ./optional/zsh.nix
      ./optional/security-tooling.nix
    ];

  home.packages = with pkgs; 
  [
    bitwarden-desktop
    #retroarch-Full
    nixos-anywhere
    colmena
    rpcs3
    game-devices-udev-rules
    firefox
    obsidian
    unstable.claude-code
    unstable.ollama
    unstable.lmstudio
    unstable.xonotic
    # unstable.jellyfin-media-player
  ];

}
