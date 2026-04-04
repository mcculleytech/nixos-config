{ pkgs, config, lib, ... }: {

  options = {
    kde.enable = lib.mkEnableOption "enables KDE Plasma desktop";
  };

  config = lib.mkIf config.kde.enable {
    services.xserver.enable = true;
    services.xserver.xkb.layout = "us";
    services.displayManager.sddm.enable = true;
    services.desktopManager.plasma6.enable = true;
    services.displayManager.defaultSession = "plasmax11";

    services.xrdp.enable = true;
    services.xrdp.defaultWindowManager = "startplasma-x11";
    services.xrdp.openFirewall = true;

    environment.systemPackages = with pkgs; [
      kdePackages.krdc
      kdePackages.kdeconnect-kde
    ];
  };
}
