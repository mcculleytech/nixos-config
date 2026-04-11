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
  };
}
