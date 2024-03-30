{ pkgs, ... }:{

  home.packages = with pkgs; 
  [ 
    spotify
    bitwarden
    terminator
    guake
    evince
    thunderbird
    nfs-utils
    yubikey-manager
    transmission-gtk
    ranger
    vlc
    appimage-run
    retroarchFull
    wakeonlan
    firefox
    epiphany
    drawing
    nixos-anywhere
    rpcs3
    game-devices-udev-rules
    # Unstable pkgs
    unstable.ollama
    unstable.hugo
    unstable.burpsuite
    unstable.quickemu
    unstable.xonotic
    unstable.obs-studio
    unstable.godot_4
    unstable.distrobox
    unstable.bolt
    unstable.thunderbolt
    unstable.jellyfin-media-player
    unstable.watchmate
    unstable.libreoffice-fresh
    unstable.protonmail-bridge
    unstable.usbutils
    unstable.element-desktop
    unstable.obsidian
    unstable.sublime4
    unstable.beeper
  ];

}
