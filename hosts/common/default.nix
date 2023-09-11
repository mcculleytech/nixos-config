# configs for various programs
{
# List of modules all systems will need
  imports = [
    ./user.nix
    ./nix-settings.nix
    ./system-packages.nix
    ./nfs.nix
    ./ssh.nix
  ];
}
