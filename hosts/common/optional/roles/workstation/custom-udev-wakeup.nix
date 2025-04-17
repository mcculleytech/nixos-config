{
  services.udev.extraRules = ''\
  SUBSYSTEM=="usb", KERNEL=="*", ACTION=="add", TEST=="power/wakeup", ATTR{power/wakeup}="enabled"
  '';
}