{ inputs, config, pkgs,  ... }: {
  imports =
    [
      ../../disko/achilles.nix
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/android.nix
      ../common/optional/cups.nix
      ../common/optional/gnome.nix
      ../common/optional/nfs.nix
      ../common/optional/syncthing.nix
      ../common/optional/virt-manager.nix
      ../common/optional/docker.nix
      ../common/optional/custom-udev.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.interfaces.enp4s0.wakeOnLan.enable = true;

  networking.hostName = "achilles";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Chicago";

  services.xserver.layout = "us";

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

  programs.dconf.enable = true;

 # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "23.11";

}

