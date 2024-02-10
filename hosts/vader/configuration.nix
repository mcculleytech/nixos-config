{ modulesPath, config, lib, pkgs, ... }:

{
  imports =
    [ 
      (modulesPath + "/installer/scan/not-detected.nix")
      (modulesPath + "/profiles/qemu-guest.nix")
      ../../disko/vader.nix
      ../common/global
      ../common/optional/gitea.nix
      # I know runners and gitea servers shouldn't be on the same server, but I'm the only one using it and can move it easily if need be :)
      ../common/optional/gitea-runners.nix
      ../common/optional/impermanence.nix
    ];

  boot.loader.grub.enable = true;
  boot.loader.grub.efiSupport = true;
  boot.loader.grub.efiInstallAsRemovable = true;

  networking.hostName = "vader"; 
  networking.networkmanager.enable = true; 

  time.timeZone = "America/Chicago";

  system.stateVersion = "23.11";

}
