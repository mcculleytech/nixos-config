{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/gitea.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "vader"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}
