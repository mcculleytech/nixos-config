{ config, lib, ... }:
let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json);
  hosts = config.lab.hosts;
in
{

  options = {
    smokeping.enable =
      lib.mkEnableOption "enables SmokePing network latency monitor";
  };

  config = lib.mkIf config.smokeping.enable {

    services.smokeping = {
      enable = true;
      host = "0.0.0.0";
      hostName = "smokeping.${tr_secrets.traefik.homelab_domain}";
      owner = "alex";
      webService = true;
      targetConfig = ''
        probe = FPing
        menu = Top
        title = Network Latency Monitoring

        + NixOS
        menu = NixOS Hosts
        title = NixOS Hosts

        ++ atreides
        menu = atreides
        title = atreides (${hosts.atreides.ip})
        host = ${hosts.atreides.ip}

        ++ phantom
        menu = phantom
        title = phantom (${hosts.phantom.ip})
        host = ${hosts.phantom.ip}

        ++ saruman
        menu = saruman
        title = saruman (${hosts.saruman.ip})
        host = ${hosts.saruman.ip}

        ++ vader
        menu = vader
        title = vader (${hosts.vader.ip})
        host = ${hosts.vader.ip}

        + Infrastructure
        menu = Infrastructure
        title = Infrastructure Devices

        ++ unifi
        menu = Unifi Router
        title = Unifi Router (${hosts.unifi.ip})
        host = ${hosts.unifi.ip}

        ++ truenas
        menu = TrueNAS
        title = TrueNAS (${hosts.truenas.ip})
        host = ${hosts.truenas.ip}

        ++ proxmox
        menu = Proxmox
        title = Proxmox (${hosts.proxmox.ip})
        host = ${hosts.proxmox.ip}

        + External
        menu = External
        title = External Targets

        ++ cloudflare
        menu = Cloudflare DNS
        title = Cloudflare DNS (1.1.1.1)
        host = 1.1.1.1

        ++ google
        menu = Google DNS
        title = Google DNS (8.8.8.8)
        host = 8.8.8.8
      '';
    };

    # smokeping uses nginx for web interface; override listen port and serverName for traefik
    services.nginx.virtualHosts.smokeping = {
      serverName = "_";
      listen = [
        { addr = "0.0.0.0"; port = 8090; }
      ];
    };

    networking.firewall.allowedTCPPorts = [ 8090 ];

    systemd.tmpfiles.rules = [
      "d /var/lib/smokeping/data 0755 smokeping smokeping -"
      "d /var/lib/smokeping/cache 0755 smokeping smokeping -"
    ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/smokeping"; user = "smokeping"; group = "smokeping"; }
        ];
      };
    };
  };

}
