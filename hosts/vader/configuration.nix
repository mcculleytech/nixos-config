{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [   
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/vader.nix
      ../common/global
      ../common/optional/roles/server/xonotic.nix
      ../common/optional/roles/server/gitea
      ../common/optional/roles/server/qemu-config.nix
    ];

  xonotic.enable = true;

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostName = "vader"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}
