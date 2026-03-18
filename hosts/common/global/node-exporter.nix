{ ... }: {
  services.prometheus.exporters.node = {
    enable = true;
    port = 9100;
    enabledCollectors = [ "systemd" ];
  };
  networking.firewall.allowedTCPPorts = [ 9100 ];
}
