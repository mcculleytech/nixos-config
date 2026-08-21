{ config, pkgs, lib, ... }: {

  options = {
    nvidia.enable = lib.mkEnableOption "enables NVIDIA drivers";
  };

  config = lib.mkIf config.nvidia.enable {
    hardware.nvidia = {
      modesetting.enable = true;
      powerManagement.enable = false;
      powerManagement.finegrained = false;
      open = false;
      nvidiaSettings = true;

      # Pascal (GTX 1080 Ti on saruman) was dropped by the 595.xx branch —
      # `stable`/`production`/`latest` all resolve to 595.71.05, which loads,
      # ignores the GPU ("NVRM: No NVIDIA GPU found"), and exits ENODEV. That
      # cascades into nvidia-cdi-generator + GPU podman units failing on
      # activation. Pascal is supported through the 580.xx Legacy branch.
      # saruman is the only host with nvidia.enable = true.
      package = config.boot.kernelPackages.nvidiaPackages.legacy_580;
    };

    environment.systemPackages = with pkgs; [
      cudaPackages.cudatoolkit
      cudaPackages.cudnn
    ];

    services.xserver.videoDrivers = [ "nvidia" ];

    # Ad hoc headless display: the 1080 Ti has no monitor attached, so SDDM never
    # starts a GPU-backed session and games render into the xorgxrdp software
    # framebuffer instead (~160ms/frame, GPU idle). Force DFP-0 "connected" with a
    # synthetic EDID so a real :0 session comes up on the GPU.
    #
    # The EDID advertises 1920x1080@60 as preferred, with 2256x1504 (3:2, the
    # Framework 13 panel) as a second detailed timing. 16:9 is preferred because
    # games are 16:9: on a 3:2 desktop a 1080p game runs windowed and centred,
    # and Remote Play captures the whole desktop, so you get KDE wallpaper framing
    # the game. Matching the desktop to the game means the capture is all game;
    # the client then letterboxes it cleanly on the 3:2 panel.
    #
    # ModeValidation: the driver validates against a fictional physical link
    # (DFP-0 has no cable), so it rejected the 2256x1504 timing outright and
    # refused every xrandr --addmode, including one at 127MHz. These tokens drop
    # the bandwidth ceilings; there is no real link to protect.
    #
    # TODO: move the EDID into the store instead of /home/alex before committing.
    services.xserver.deviceSection = ''
      Option "ConnectedMonitor" "DFP-0"
      Option "CustomEDID" "DFP-0:/home/alex/edid-game.bin"
      Option "AllowEmptyInitialConfiguration" "true"
      Option "ModeValidation" "DFP-0: NoMaxPClkCheck, NoEdidMaxPClkCheck, NoVertRefreshCheck, NoHorizSyncCheck, AllowNonEdidModes"
    '';

    hardware.nvidia-container-toolkit.enable = true;

    # GPU metrics for Prometheus. nvidia_gpu_exporter wraps `nvidia-smi`
    # and exposes utilization, memory, temperature, power, and process
    # info as Prometheus metrics. Co-located with the NVIDIA module so
    # any host that turns on `nvidia.enable` automatically gets the
    # exporter — no per-host duplication.
    services.prometheus.exporters.nvidia-gpu = {
      enable = true;
      port = 9835;
    };
    networking.firewall.allowedTCPPorts = [ 9835 ];
  };
}
