{ inputs, config, pkgs, lib,  ... }: {
  imports =
    [
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/roles/server
      ../common/optional/docker.nix
      ../common/optional/roles/workstation/kde.nix
      ../common/optional/roles/workstation/steam.nix
      ../common/optional/nvidia.nix
      ../common/optional/opengl.nix
      ../common/optional/roles/workstation/bluetooth.nix
      ../../disko/saruman.nix
    ];

  jellyfin.enable = true;
  octoprint.enable = true;
  ollama.enable = true;
  steam.enable = true;
  immich.enable = true;
  open-webui.enable = true;


  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.interfaces.enp5s0.wakeOnLan.enable = true;

  environment.systemPackages = with pkgs; [
    unstable.nvidia-docker
    unstable.flameshot
    unstable.zrok
  ];

  # virtualisation.docker = {
  #   enableNvidia = true;
  # };

  networking.hostName = "saruman";
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
  system.stateVersion = "24.05";

}
