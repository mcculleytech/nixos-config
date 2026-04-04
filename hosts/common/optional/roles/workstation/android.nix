{ config, pkgs, lib, ... }: {

  options = {
    android.enable = lib.mkEnableOption "enables android development tools";
  };

  config = lib.mkIf config.android.enable {
    programs.adb.enable = true;
    users.users.alex.extraGroups = ["adbusers"];
    # need to configure normal udev rules for this.
    # services.udev.packages = [
    #   pkgs.android-udev-rules
    # ];
  };
}
