{ pkgs, ... }:
{
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
    drawing
    nixos-anywhere
    rpcs3
    game-devices-udev-rules
    remmina
    google-chrome
    zrok
    calibre
    protonvpn-gui
    watchmate
    cura
    minetestclient
    gparted
    rpi-imager
    unetbootin
    isoimagewriter
    # Unstable pkgs
    unstable.hexchat
    unstable.signal-desktop
    unstable.ollama
    unstable.metasploit
    unstable.hugo
    unstable.burpsuite
    unstable.xonotic
    unstable.obs-studio
    unstable.godot_4
    unstable.distrobox
    unstable.bolt
    unstable.thunderbolt
    unstable.jellyfin-media-player
    unstable.libreoffice-fresh
    unstable.protonmail-bridge
    unstable.usbutils
    unstable.element-desktop
    unstable.obsidian
    unstable.sublime4
    unstable.beeper
  ];
}
