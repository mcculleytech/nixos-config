{ pkgs, ouputs, ... }: {

  home.packages = with pkgs; 
  [ 
    unstable.hashcat
  ];

}
