{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      ./optional/terminator.nix
      ./optional/zsh.nix
      ./optional/security-tooling.nix
      ./optional/nvim
    ];

    terminator.enable = true;
    zsh.enable = true;
    security-tooling.enable = true;
    nvim.enable = true;

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

  services.protonmail-bridge.enable = true;

}
