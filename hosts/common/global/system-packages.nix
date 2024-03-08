{pkgs, ...}: {
  # Configure Systemwide Packages
  environment.systemPackages = with pkgs; 
  [
    vim
    wget
    git
    tmux
    tree
    neofetch
    zsh
    htop
    sops
    util-linux
    exfatprogs
    nfs-utils
    nmap
  ];

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
  ];

  programs.zsh.enable = true;

}
