{ inputs, config, pkgs,  ... }: {
  imports =
    [
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/docker.nix
      ../common/optional/nvidia.nix
      ../common/optional/opengl.nix
      ../common/optional/roles/workstation
      ../../disko/achilles.nix
    ];

  # module enable
  docker.enable = true;
  nvidia.enable = true;
  opengl.enable = true;
  steam.enable = true;
  android.enable = true;
  cups.enable = true;
  syncthing-workstation.enable = true;
  virt-manager.enable = true;
  custom-udev.enable = true;
  game-controllers.enable = true;
  vmware.enable = true;
  gnome.enable = true;
  bluetooth.enable = true;

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.interfaces.enp4s0.wakeOnLan.enable = true;

  # additional services and configs
  workstation-user-options.enable = true;

  environment.systemPackages = with pkgs; [
    unstable.nvidia-docker
    unstable.flameshot
  ];

  hardware.nvidia-container-toolkit.enable = true;

  networking.hostName = "achilles";
  networking.networkmanager.enable = true;

  time.timeZone = "America/Chicago";

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
