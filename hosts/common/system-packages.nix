{pkgs, ...}: {
  # Configure Systemwide Packages
  environment.systemPackages = with pkgs; 
  [
    firefox
    vim
    wget
    git
    tmux
    tree
    neofetch
    zsh
    htop
    bolt
    thunderbolt
  ];

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
  ];

  programs.zsh.enable = true;

}
