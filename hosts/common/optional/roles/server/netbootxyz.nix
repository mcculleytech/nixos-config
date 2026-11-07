{ config, lib, ... }: {

  options.netbootxyz = {
    enable = lib.mkEnableOption "netboot.xyz container (web UI + TFTP + HTTP assets) with proxyDHCP";

    dataDir = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas-backups/pixiecore";
      description = ''
        Storage for the container's /assets (boot media, e.g. an extracted
        Windows ISO). Lives on the NAS because boot media are bulky.
      '';
    };

    configDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/netbootxyz";
      description = ''
        Container /config (menus + web app state). Must be LOCAL, not NFS: the
        container's TFTP runs with --tftp-secure, which only serves files owned
        by its own user (nbxyz, uid 1000). On the NAS export root-squash created
        them as uid 34, so every client got "No such file or directory".
      '';
    };

    serverIp = lib.mkOption {
      type = lib.types.str;
      default = "10.1.8.6";
      description = "Address clients are told to fetch TFTP/HTTP from.";
    };

    subnet = lib.mkOption {
      type = lib.types.str;
      default = "10.1.8.0";
      description = "Broadcast domain proxyDHCP answers on (PXE does not cross VLANs).";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      default = "enp5s0";
      description = "Interface proxyDHCP binds to.";
    };

    webPort = lib.mkOption {
      type = lib.types.port;
      default = 3001;
      description = "netboot.xyz web configuration UI (3000 is taken by gotenberg/paperless).";
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 80;
      description = "nginx serving menus and assets.";
    };
  };

  config = lib.mkIf config.netbootxyz.enable {

    # The upstream container bundles the menu webapp, nginx (assets) and dnsmasq
    # in TFTP-only mode. It deliberately does NOT serve DHCP — a client must be
    # handed the iPXE bootfile by something else, which is the dnsmasq proxyDHCP
    # below. That keeps the router untouched.
    virtualisation.oci-containers.containers.netbootxyz = {
      image = "ghcr.io/netbootxyz/netbootxyz:latest";
      ports = [
        "${toString config.netbootxyz.webPort}:3000"
        "${toString config.netbootxyz.httpPort}:80"
        "69:69/udp"
      ];
      volumes = [
        "${config.netbootxyz.configDir}:/config"
        "${config.netbootxyz.dataDir}/assets:/assets"
      ];
      environment = {
        NGINX_PORT = "80";
        WEB_APP_PORT = "3000";
      };
    };

    # /config lives on local disk so the container owns its own menu/bootloader
    # files (see configDir above); persist it across the ephemeral root.
    environment.persistence."/persist".directories = [ config.netbootxyz.configDir ];

    # proxyDHCP: answers PXE requests alongside the router's DHCP without
    # allocating addresses, so nothing on the router has to change. dnsmasq does
    # NOT run its own TFTP here — port 69 belongs to the container.
    services.dnsmasq = {
      enable = true;
      settings = {
        port = 0;                       # no DNS service
        interface = config.netbootxyz.interface;
        "bind-interfaces" = true;
        "log-dhcp" = true;
        "dhcp-range" = "${config.netbootxyz.subnet},proxy,255.255.255.0";
        "pxe-service" = [
          "x86PC,netboot.xyz,netboot.xyz.kpxe"
          "X86-64_EFI,netboot.xyz,netboot.xyz.efi"
          "BC_EFI,netboot.xyz,netboot.xyz.efi"
        ];
      };
    };

    networking.firewall = {
      allowedTCPPorts = [ config.netbootxyz.webPort config.netbootxyz.httpPort ];
      allowedUDPPorts = [ 69 ];
    };
  };
}
