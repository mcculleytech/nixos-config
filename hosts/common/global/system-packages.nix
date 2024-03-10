{pkgs, ...}: {
  # Configure Systemwide Packages
  environment.systemPackages = with pkgs; 
  [
    vim
    wget
    git
    git-crypt
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
    age
    ssh-to-age
  ];

  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
  ];

  programs.zsh.enable = true;

}
