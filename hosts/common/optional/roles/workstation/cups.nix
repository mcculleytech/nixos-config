{pkgs, config, ... }:

{
  services.printing.enable = true;
  services.avahi.enable = true;
  services.avahi.nssmdns = true;
  # for a WiFi printer
  services.avahi.openFirewall = true;
  services.printing.drivers = with pkgs; [
    brgenml1lpr
    brgenml1cupswrapper
    brlaser
  ];

}
