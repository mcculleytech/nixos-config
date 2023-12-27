{config, pkgs, ...}:
{
  programs.adb.enable = true;
  users.users.alex.extraGroups = ["adbusers"];
  services.udev.packages = [
    pkgs.android-udev-rules
  ];
}
