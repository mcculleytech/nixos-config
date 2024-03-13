{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [   
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/atreides.nix
      ../common/global
      ../common/optional/roles/server/qemu-config.nix
      ../common/optional/roles/server/blocky.nix
      ../common/optional/roles/server/homepage-dashboard.nix
    ];

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostName = "atreides"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}