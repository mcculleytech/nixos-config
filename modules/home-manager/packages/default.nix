{ pkgs, ouputs, ... }: {

  home.packages = with pkgs; 
  [ 
    spotify
    bitwarden
    terminator
    guake
    zoom-us
    nextcloud-client
    # Unstable pkgs
    unstable.fwupd
    unstable.bolt
    unstable.thunderbolt
    unstable.usbutils
    unstable.element-desktop
    unstable.obsidian
    unstable.sublime4
    unstable.rpcs3
    unstable.beeper
  ];

}
