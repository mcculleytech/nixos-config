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

      package = config.boot.kernelPackages.nvidiaPackages.stable;
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
