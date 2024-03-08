{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [   
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/phantom.nix
      ../common/global
      ../common/optional/qemu-config.nix
    ];

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  # enable ip forwarding for TS Router.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;

  networking.hostName = "phantom"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}