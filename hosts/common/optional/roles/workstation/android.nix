{config, pkgs, ...}:
{
  programs.adb.enable = true;
  users.users.alex.extraGroups = ["adbusers"];
  # need to configure normal udev rules for this.
  # services.udev.packages = [
  #   pkgs.android-udev-rules
  # ];
}
