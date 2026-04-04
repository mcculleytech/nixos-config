{ config, lib, ... }: {

  options = {
    custom-udev-wakeup.enable = lib.mkEnableOption "enables USB wakeup udev rules";
  };

  config = lib.mkIf config.custom-udev-wakeup.enable {
    services.udev.extraRules = ''
      SUBSYSTEM=="usb", KERNEL=="*", ACTION=="add", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"
    '';
  };
}
