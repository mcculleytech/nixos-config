{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/atreides.nix
      ../common/global
      ../common/optional/docker.nix
      ../common/optional/roles/server
    ];

  # module enable
  qemuGuest.enable = true;
  blocky.enable = true;
  homepage-dashboard.enable = true;
  traefik.enable = true;
  home-impermanence = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostName = "atreides";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}
