{ pkgs, config, lib, ... }: {

  options = {
    cava.enable = lib.mkEnableOption "enables cava audio visualizer";
  };

  config = lib.mkIf config.cava.enable {
    home.packages = [ pkgs.cava ];

    xdg.configFile."cava/config".text = ''
      [general]
      framerate = 60
      bars = 0
      bar_width = 2
      bar_spacing = 1

      [input]
      method = pipewire
      source = auto

      [color]
      gradient = 1
      gradient_count = 4
      gradient_color_1 = '#81A1C1'
      gradient_color_2 = '#88C0D0'
      gradient_color_3 = '#8FBCBB'
      gradient_color_4 = '#A3BE8C'
    '';
  };
}
