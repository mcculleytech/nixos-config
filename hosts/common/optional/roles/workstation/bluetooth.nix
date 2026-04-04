{ pkgs, config, lib, ... }: {

  options = {
    bluetooth.enable = lib.mkEnableOption "enables bluetooth support";
  };

  config = lib.mkIf config.bluetooth.enable {
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = true;
  };
}
