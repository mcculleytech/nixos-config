{
  imports = [
    ./env-vars.nix
    ./ephemeral-btrfs.nix
    ./impermanence.nix
    ./nix-settings.nix
    ./sops.nix
    ./ssh.nix
    ./system-packages.nix
    ./systemd-initrd.nix
    ./tailscale.nix
    ./users/alex
  ];
}
