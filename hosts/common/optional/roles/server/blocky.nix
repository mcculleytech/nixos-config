{ inputs, config, pkgs, lib, ... }:
let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json);
  hosts = config.lab.hosts;
in
{

 	options = {
		blocky.enable =
			lib.mkEnableOption "enables blocky DNS server";
	};

	config = lib.mkIf config.blocky.enable {

	   services.blocky = {
	   	enable = true;
      	settings = {
      		upstreams = {
      			groups = {
      				default = [
      					"1.1.1.1"
      					"1.0.0.1"
      				];
      			};
      		};
      		customDNS = {
      			mapping = {
      				# nix subnet
      				"atreides.${tr_secrets.traefik.server_domain}" = hosts.atreides.ip;
      				"phantom.${tr_secrets.traefik.server_domain}" = hosts.phantom.ip;
      				# dmz subnet
      				"vader.${tr_secrets.traefik.dmz_domain}" = hosts.vader.ip;
      				"prdcoffeeubuntu.${tr_secrets.traefik.dmz_domain}" = hosts.prdcoffeeubuntu.ip;
      				# homelab domain — all reverse-proxied via atreides (traefik)
      				"jellyfin.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"ilo.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"source.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"ai.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"immich.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"dashboard.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"traefik.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"proxmox.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"unifi.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"truenas.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"octoprint.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"octostream.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"syncthing.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"radicale.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"n8n.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"miniflux.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"paperless.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"grafana.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"prometheus.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      				"smokeping.${tr_secrets.traefik.homelab_domain}" = hosts.atreides.ip;
      			};
      		};
      		blocking = {
      			blackLists = {
      				ads = [
      					"https://blocklistproject.github.io/Lists/ads.txt"
      				];
      			};
      		};
        		prometheus = {
        			enable = true;
        			path = "/metrics";
        		};
        		ports = {
        			dns = 53;
        			http = 4000;
        		};
        		# For initially solving DoH/DoT Requests when no system Resolver is available.
        		bootstrapDns = {
        		  upstream = "https://one.one.one.one/dns-query";
        		  ips = [ "1.1.1.1" "1.0.0.1" ];
        		};
	   	};
	   };
    	networking.firewall.allowedTCPPorts = [ 53 4000 ];
    	networking.firewall.allowedUDPPorts = [ 53 ];
	};
}
