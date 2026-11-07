{ config, lib, ... }: {

  options.pixiecore = {
    enable = lib.mkEnableOption "Pixiecore PXE/ProxyDHCP boot server serving the netboot.xyz menu";

    assetsDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas-backups/pixiecore";
      description = ''
        Directory holding boot images and ISOs, served over HTTP. Defaults to the
        NAS export (/mnt/nas-backups, ~2.2T free) because boot media are bulky.
        Point it at /var/lib/pixiecore to keep the store local instead.
        The directory is created once by hand; this module does not manage it,
        so a missing NAS mount never fails the boot.
      '';
    };

    assetsPort = lib.mkOption {
      type = lib.types.port;
      default = 8090;
      description = "HTTP port serving assetsDir (autoindex, read-only paths).";
    };
  };

  config = lib.mkIf config.pixiecore.enable {

    # ProxyDHCP: pixiecore answers alongside the network's existing DHCP server
    # (dhcpNoBind), so no option 66/67 changes are needed on the router. PXE is
    # broadcast-scoped — every VLAN that should netboot needs its own responder,
    # which is why this lives on one flat segment rather than covering the range.
    services.pixiecore = {
      enable = true;
      openFirewall = true;
      dhcpNoBind = true;
      # Local HTTP-only chainload script. Pointing this at https://boot.netboot.xyz
      # does not work from stock pixiecore iPXE: it ships no CA bundle, so the TLS
      # chain times out (ipxe.org/4c126035) and the guest parks in pixiecore's own
      # "Boot from local hdd" menu instead of reaching netboot.xyz.
      kernel = "${config.pixiecore.assetsDir}/boot.ipxe";
    };

    # Static HTTP for the asset store: ISOs download directly, and mirrored
    # netboot.xyz assets can be served from here for offline booting.
    services.nginx = {
      enable = true;
      virtualHosts."pixiecore-assets" = {
        listen = [ { addr = "0.0.0.0"; port = config.pixiecore.assetsPort; } ];
        root = config.pixiecore.assetsDir;
        locations."/".extraConfig = "autoindex on;";
      };
    };

    networking.firewall.allowedTCPPorts = [ config.pixiecore.assetsPort ];
  };
}
