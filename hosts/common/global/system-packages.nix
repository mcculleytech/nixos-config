{pkgs, ...}: {
  # Configure Systemwide Packages
  environment.systemPackages = with pkgs;
  [
    vim
    bitwarden-cli
    dnsutils
    wget
    gh
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
    unstable.opencode
  ];
  fonts.packages = with pkgs; [
    nerd-fonts.fira-code
    nerd-fonts.droid-sans-mono
  ];

}
