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

    # xrdp removed 2026-08-20. It ran a second Plasma session (on :10, backed by
    # the xorgxrdp software framebuffer), and Plasma cannot run twice for one
    # user: KWin and plasmashell are singletons on the per-user D-Bus at
    # /run/user/1000/bus. Whichever session started first held org.kde.KWin, so
    # the seat0 gaming session came up with no window manager at all — unmanaged,
    # uncentred windows that would not go fullscreen. It was also where games
    # landed before the GPU-backed :0 session existed, costing ~160ms/frame.
    # Admin is SSH; games are Steam Remote Play against :0.
    # If a graphical remote path is ever needed again, do NOT point it at
    # startplasma-x11 — use a WM that does not claim the KDE bus names.

    environment.systemPackages = with pkgs; [
      kdePackages.krdc
      kdePackages.kdeconnect-kde
    ];
  };
}
