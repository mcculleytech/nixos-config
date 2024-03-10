{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [   
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/phantom.nix
      ../common/global
      ../common/optional/qemu-config.nix
      ../common/optional/tailscale_server.nix
    ];

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostName = "phantom"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}