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
