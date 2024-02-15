{

  imports = [
    ./env-vars.nix
    ./nix-settings.nix
    ./ssh.nix
    ./system-packages.nix
    ./user.nix
    #./sops.nix
    #./tailscale.nix
    ./systemd-initrd.nix
  ];



}
