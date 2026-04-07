{
  imports = [
    ./hosts.nix
    ./env-vars.nix
    ./ephemeral-btrfs.nix
    ./node-exporter.nix
    ./impermanence.nix
    ./nix-settings.nix
    ./sops.nix
    ./ssh.nix
    ./system-packages.nix
    ./systemd-initrd.nix
    ./tailscale.nix
    ./networkmanager.nix
    ./users/alex
  ];
}
