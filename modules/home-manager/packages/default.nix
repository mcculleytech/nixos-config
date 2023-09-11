{ pkgs, ouputs, ... }: {

  home.packages = with pkgs; 
  [ 
    spotify
    bitwarden
    element-desktop
    terminator
    # Unstable packages
    unstable.obsidian
    unstable.sublime4
    unstable.rpcs3
  ];

}
