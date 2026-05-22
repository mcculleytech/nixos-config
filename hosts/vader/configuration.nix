{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/vader.nix
      ../common/global
      ../common/optional
      ../common/optional/roles/server
    ];

  xonotic.enable = true;
  qemuGuest.enable = true;
  gitea.enable = true;
  home-impermanence.enable = true;

  # Vader is on the DMZ subnet (10.2.1.x); atreides is on the nix subnet
  # (10.1.8.x) and inter-subnet 3100 is firewalled at the router. Route
  # Alloy → Loki over the tailnet instead so the existing tailscale
  # peering carries the traffic.
  lab.alloy.lokiHost = config.lab.hosts.atreides.tailnetIp;

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostName = "vader";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}
