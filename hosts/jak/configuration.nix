{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../../disko/workstation.nix
      ../common/optional/roles/workstation/budgie.nix
      ../common/optional/roles/workstation
      ../common/global
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "jak"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}