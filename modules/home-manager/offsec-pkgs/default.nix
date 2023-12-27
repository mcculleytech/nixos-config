{ pkgs, ouputs, ... }: {

  home.packages = with pkgs; 
  [ 
    unstable.hashcat
    unstable.seclists
  ];

}
