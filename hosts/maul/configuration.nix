{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/laptop-power-settings.nix
      ../common/optional/nfs-server.nix
      #../common/optional/server-user-customizations.nix
      ../common/optional/backup-server-syncthing.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "maul"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "unstable";

}
