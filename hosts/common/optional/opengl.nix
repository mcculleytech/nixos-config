{ pkgs, config, lib, ... }: {

  options = {
    opengl.enable = lib.mkEnableOption "enables OpenGL/graphics support";
  };

  config = lib.mkIf config.opengl.enable {
    hardware.graphics = {
      enable = true;

      enable32Bit = true;
    };
  };
}
