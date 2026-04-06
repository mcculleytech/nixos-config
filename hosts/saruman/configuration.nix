{ inputs, config, pkgs, lib,  ... }: {
  imports =
    [
      ./hardware-configuration.nix
      ../common/global
      ../common/optional
      ../common/optional/roles/server
      ../common/optional/roles/workstation
      ../../disko/saruman.nix
    ];

  # module enable
  docker.enable = true;
  nvidia.enable = true;
  opengl.enable = true;
  jellyfin.enable = true;
  octoprint.enable = true;
  ollama.enable = true;
  steam.enable = true;
  immich.enable = true;
  open-webui.enable = true;
  n8n.enable = true;
  paperless.enable = true;
  kde.enable = true;
  bluetooth.enable = true;
  auto-deploy.enable = true;
  tailscale-server.enable = true;


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

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  programs.dconf.enable = true;

 # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.05";

}
