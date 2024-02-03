
{ inputs, lib, config, pkgs, ... }: {
  # You can import other NixOS modules here
  imports = [
    ./hardware-configuration.nix
    ../common/global
    ../../modules/nixos/aeneas.nix
  ];

  networking.hostName = "aeneas";

  boot.loader.systemd-boot.enable = true;

  services.hardware.bolt.enable = true;

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Configure keymap in X11
  services.xserver.layout = "us";

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  hardware.pulseaudio.enable = false;
  # rtkit is optional but recommended
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
  system.autoUpgrade.enable = true;
}
