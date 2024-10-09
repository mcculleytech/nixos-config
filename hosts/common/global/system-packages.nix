{pkgs, ...}: {
  # Configure Systemwide Packages
  environment.systemPackages = with pkgs; 
  [
    vim
    bitwarden-cli
    dnsutils
    wget
    git
    git-crypt
    tmux
    tree
    neofetch
    htop
    sops
    util-linux
    exfatprogs
    nfs-utils
    nmap
    age
    ssh-to-age
    p7zip
    usbutils
    e2fsprogs
    cachix
    nixos-anywhere
  ];
  fonts.packages = with pkgs; [
    (nerdfonts.override { fonts = [ "FiraCode" "DroidSansMono" ]; })
  ];

}
