{ inputs, config, pkgs, ... }: {
  imports = 
    [
      ../../disko/aeneas.nix
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/android.nix
      ../common/optional/cups.nix
      ../common/optional/gnome.nix
      #../common/optional/nfs.nix
      ../common/optional/syncthing.nix
      ../common/optional/virt-manager.nix
      ../common/optional/docker.nix
      ../common/optional/custom-udev.nix
    ];
  
  networking.hostName = "aeneas";
  boot.loader.systemd-boot.enable = true;

  # Latest Kernel fixes some issues on Framework
  boot.kernelPackages = pkgs.linuxPackages_latest;


  services.power-profiles-daemon = {
    enable = true;
  };

  services.fprintd = {
    enable = true;
  };

  services.hardware.bolt.enable = true;
  
  time.timeZone = "America/Chicago";
  
  services.xserver.layout = "us";
  
  services.printing.enable = true;
  
  hardware.pulseaudio.enable = false;
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
