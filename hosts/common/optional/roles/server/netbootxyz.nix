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

    # The container bind-mounts /assets from the NAS. Without an explicit
    # dependency it races the NFS automount on a cold boot and podman dies with
    # "statfs /mnt/nas-backups/pixiecore/assets: no such device" before the
    # mount is established.
    systemd.services."podman-netbootxyz" = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      unitConfig.RequiresMountsFor = "${config.netbootxyz.dataDir}/assets";
    };

    # proxyDHCP: answers PXE requests alongside the router's DHCP without
    # allocating addresses. The router's own Network Boot options never reach
    # clients on this VLAN, so this is what actually hands out the bootfile.
    # dnsmasq does NOT run TFTP here; port 69 belongs to the container.
    services.dnsmasq = {
      enable = true;
      resolveLocalQueries = false;
      settings = {
        port = 0;                       # no DNS service
        interface = config.netbootxyz.interface;
        "bind-interfaces" = true;
        "log-dhcp" = true;
        "dhcp-range" = "${config.netbootxyz.subnet},proxy,255.255.255.0";
        "dhcp-match" = [
          "set:bios,option:client-arch,0"
          "set:efi64,option:client-arch,7"
          "set:efi64,option:client-arch,9"
        ];
        "dhcp-boot" = [
          "tag:bios,netboot.xyz.kpxe,,${config.netbootxyz.serverIp}"
          "tag:efi64,netboot.xyz.efi,,${config.netbootxyz.serverIp}"
        ];
        "pxe-service" = [
          "tag:bios,x86PC,netboot.xyz,netboot.xyz.kpxe,${config.netbootxyz.serverIp}"
          "tag:efi64,X86-64_EFI,netboot.xyz,netboot.xyz.efi,${config.netbootxyz.serverIp}"
          "tag:efi64,BC_EFI,netboot.xyz,netboot.xyz.efi,${config.netbootxyz.serverIp}"
        ];
      };
    };

    # dnsmasq binds a specific interface (bind-interfaces), so it fails hard with
    # "unknown interface <if>" if it starts before the link exists — which is
    # exactly what happened on a cold boot. Wait for the network instead of
    # needing a manual restart after every reboot.
    systemd.services.dnsmasq = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
    };

    networking.firewall = {
      allowedTCPPorts = [ config.netbootxyz.webPort config.netbootxyz.httpPort ];
      allowedUDPPorts = [ 67 69 4011 ];  # proxyDHCP, TFTP, PXE boot server
    };
  };
}
