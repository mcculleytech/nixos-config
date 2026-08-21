{ pkgs, config, lib, ... }: {

  options = {
    gamescope.enable = lib.mkEnableOption "enables the gamescope micro-compositor";
  };

  config = lib.mkIf config.gamescope.enable {
    programs.gamescope = {
      enable = true;
      # capSysNice intentionally left off: setcap binaries drop LD_PRELOAD,
      # which breaks the Steam overlay and Proton launches.
    };
  };
}
