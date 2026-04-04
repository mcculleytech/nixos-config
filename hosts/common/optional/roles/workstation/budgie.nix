{ config, lib, ... }: {

  options = {
    budgie.enable = lib.mkEnableOption "enables Budgie desktop";
  };

  config = lib.mkIf config.budgie.enable {
    services.xserver.enable = true;
    services.xserver.desktopManager.budgie.enable = true;
    services.xserver.displayManager.lightdm.enable = true;
  };
}
