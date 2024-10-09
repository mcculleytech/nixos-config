{ pkgs, ... }:{

  home.packages = with pkgs; 
  [ 
    unstable.hashcat
    unstable.metasploit
    unstable.burpsuite
  ];

}