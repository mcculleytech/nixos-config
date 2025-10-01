{ inputs, config, pkgs, ... }:
{
  imports = 
    [
      ../../disko/aeneas.nix
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/docker.nix
      #../common/optional/pam-auth.nix
      ../common/optional/roles/workstation
      #../common/optional/roles/workstation/hyprland
      ../common/optional/roles/workstation/cosmic.nix
      ../common/optional/roles/workstation/gnome.nix
      #../common/optional/roles/workstation/vmware.nix
      ../common/optional/roles/workstation/custom-udev-wakeup.nix
      #../common/optional/roles/workstation/acpi_wakeup.nix
      ../common/optional/roles/workstation/framework-tweaks.nix
    ];

  # module enable
  steam.enable = true;
  
  networking.hostName = "aeneas";
  networking.networkmanager.enable = true;

  hardware.graphics.enable = true; 

  # additional services and configs
  workstation-user-options.enable = true;

  boot.loader.systemd-boot.enable = true;

  # Latest Kernel fixes some issues on Framework
  boot.kernelPackages = pkgs.linuxPackages_latest;
  #boot.kernelPackages = pkgs.linuxKernel.packages.linux_6_12;

  services.hardware.bolt.enable = true;
  
  time.timeZone = "America/Chicago";
  
  services.xserver.xkb.layout = "us";
  
  services.printing.enable = true;


  hardware.bluetooth.enable = true;
  
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;
  };
  
  
  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";
}
