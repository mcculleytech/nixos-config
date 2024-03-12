{ inputs, config, pkgs, ... }: {
	
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
    				"truenas.nix.mcculley.tech" = "10.1.8.4";
    				"devdockerubuntu.nix.mcculley.tech" = "10.1.8.3";
    				"homer.nix.mcculley.tech" = "10.1.8.3";
    				"jellyfin.nix.mcculley.tech" = "10.1.8.3";
    				"jackett.nix.mcculley.tech" = "10.1.8.3";
    				"octopi.nix.mcculley.tech" = "10.1.8.3";
    				"transmission.nix.mcculley.tech" = "10.1.8.3";
    				# pve subnet
    				"proxmox.pve.mcculley.tech" = "10.1.8.3";
    				# dmz subnet
    				"prdcloudubuntu.dmz.mcculley.tech" = "10.2.1.2";
    				"prddockerubuntu00.dmz.mcculley.tech" = "10.2.1.17";
    				"prdcoffeeubuntu.dmz.mcculley.tech" = "10.2.1.6";
    				# lan subnet
    				"unifi.lan.mcculley.tech" = "10.1.8.3";
    				# lab subnet
   					"achilles.lab.mcculley.tech" = "10.0.0.2";

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
}