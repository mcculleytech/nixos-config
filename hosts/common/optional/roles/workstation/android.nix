{ config, pkgs, lib, ... }: {

  options = {
    android.enable = lib.mkEnableOption "enables android development tools";
  };

  config = lib.mkIf config.android.enable {
    # `programs.adb.enable` was removed upstream — systemd 258 handles
    # uaccess for adb's USB devices automatically, so the option is a
    # no-op and now an assertion failure. Just ship the binary.
    environment.systemPackages = [ pkgs.android-tools ];
    # The adbusers group is also gone (uaccess replaces it); leaving
    # alex in any pre-existing adbusers group is harmless if it still
    # exists in /etc/group, but no longer needed for permission.
    # need to configure normal udev rules if you want auto-detection
    # of phones in fastboot/recovery modes:
    # services.udev.packages = [ pkgs.android-udev-rules ];
  };
}
