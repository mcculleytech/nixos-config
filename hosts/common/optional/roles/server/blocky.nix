{ inputs, config, pkgs, lib, ... }:
let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json);
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
      				"atredies.${tr_secrets.traefik.server_domain}" = "10.1.8.129";
      				"phantom.${tr_secrets.traefik.server_domain}" = "10.1.8.121";
      				# dmz subnet
      				"vader.${tr_secrets.traefik.dmz_domain}" = "10.2.1.245";
      				"prddockerubuntu00.${tr_secrets.traefik.dmz_domain}" = "10.2.1.17";
      				"prdcoffeeubuntu.${tr_secrets.traefik.dmz_domain}" = "10.2.1.6";
      				"housetohome.${tr_secrets.traefik.dmz_domain}" = "10.2.1.113";
     					# homelab domain
     					"jellyfin.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
     					"ilo.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
     					"source.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
     					"ai.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
     					"immich.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"dashboard.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"traefik.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"proxmox.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"ludus.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"unifi.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"truenas.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"octoprint.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"octostream.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"syncthing.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      				"radicale.${tr_secrets.traefik.homelab_domain}" = "10.1.8.129";
      			};
      		};
      		blocking = {
      			blackLists = {
      				ads = [
      					"https://blocklistproject.github.io/Lists/ads.txt"
      				];
      			};
      		};
        		ports = {
        			dns = 53;
        		};
        		# For initially solving DoH/DoT Requests when no system Resolver is available.
        		bootstrapDns = {
        		  upstream = "https://one.one.one.one/dns-query";
        		  ips = [ "1.1.1.1" "1.0.0.1" ];
        		};
	   	};
	   };
    	networking.firewall.allowedTCPPorts = [ 53 ];
    	networking.firewall.allowedUDPPorts = [ 53 ];
	};
}
