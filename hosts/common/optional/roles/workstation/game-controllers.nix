{ pkgs, config, lib, ... }: {

  options = {
    game-controllers.enable = lib.mkEnableOption "enables game controller support";
  };

  config = lib.mkIf config.game-controllers.enable {
    environment.systemPackages = with pkgs; [
      antimicrox
    ];
  };
}
