{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/vader.nix
      ../common/global
      ../common/optional/roles/server
    ];

  xonotic.enable = true;
  qemuGuest.enable = true;
  gitea.enable = true;
  home-impermanence.enable = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostName = "vader";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}
