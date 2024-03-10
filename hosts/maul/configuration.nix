{ config, pkgs, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/roles/server/laptop-power-settings.nix
      ../common/optional/roles/server/nfs-server.nix
      ../common/optional/roles/server/backup-server-syncthing.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "maul"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}
