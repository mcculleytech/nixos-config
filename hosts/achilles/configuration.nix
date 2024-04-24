{ inputs, config, pkgs,  ... }: {
  imports =
    [
      ./hardware-configuration.nix
      ../common/global
      ../common/optional/docker.nix
      #../common/optional/nfs.nix
      ../common/optional/roles/workstation
      #../common/optional/ollama.nix
      ../common/optional/roles/workstation/gnome.nix
      ../../disko/achilles.nix
    ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.interfaces.enp4s0.wakeOnLan.enable = true;

  environment.systemPackages = with pkgs; [
    unstable.nvidia-docker
    unstable.flameshot
  ];

  virtualisation.virtualbox.host.enable = true;
  virtualisation.virtualbox.host.enableHardening = false;
  users.extraGroups.vboxusers.members = [ "alex" ];

  virtualisation.docker = {
    enableNvidia = true;
  };

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

