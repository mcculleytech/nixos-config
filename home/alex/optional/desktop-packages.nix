{ pkgs, ouputs, ... }: {

  home.packages = with pkgs; 
  [ 
    spotify
    bitwarden
    terminator
    guake
    okular
    thunderbird
    nfs-utils
    flameshot
    yubikey-manager
    transmission-gtk
    ranger
    vlc
    nixos-anywhere
    # Unstable pkgs
    unstable.mgba
    unstable.appimage-run
    unstable.xonotic
    unstable.obs-studio
    unstable.godot_4
    unstable.distrobox
    unstable.firefox
    unstable.bolt
    unstable.thunderbolt
    unstable.google-chrome
    unstable.jellyfin-media-player
    unstable.watchmate
    unstable.libreoffice-fresh
    unstable.protonmail-bridge
    unstable.fwupd
    unstable.usbutils
    unstable.element-desktop
    unstable.obsidian
    unstable.sublime4
    unstable.rpcs3
    unstable.beeper
  ];

}
