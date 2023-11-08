{ pkgs, ouputs, ... }: {

  home.packages = with pkgs; 
  [ 
    spotify
    bitwarden
    terminator
    guake
    nextcloud-client
    okular
    thunderbird
    nfs-utils
    flameshot
    yubikey-manager
    # Unstable pkgs
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
