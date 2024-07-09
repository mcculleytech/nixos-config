{ config, ... }:
let 
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../../secrets/git_crypt_traefik.json);
in 
{
	services.traefik.dynamicConfigOptions = {
		tls = {
			stores = {
					default = {
						defaultGeneratedCert = {
							resolver = "cloudflare";
							domain = {
								main = "${tr_secrets.traefik.homelab_domain}"; sans = [ "*.${tr_secrets.traefik.homelab_domain}" ]; 
							};
						};
					};
				};
			};
		# Remember to make a DNS entry and ensure that Firewall ports are open for services!
		http = {
			routers = {
				# begin Routers
				dashboard = {
					entryPoints = [ "websecure" ];
					rule = "Host(`dashboard.${tr_secrets.traefik.homelab_domain}`)";
					middlewares = [ "default-headers" "https-redirectscheme" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "dashboard";
				};
				proxmox = {
					entryPoints = [ "websecure" ];
					rule = "Host(`proxmox.${tr_secrets.traefik.homelab_domain}`)";
					middlewares = [ "default-headers" "https-redirectscheme" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "proxmox";
				};
				unifi = {
					entryPoints = [ "websecure" ];
					rule = "Host(`unifi.${tr_secrets.traefik.homelab_domain}`)";
					middlewares = [ "default-headers" "https-redirectscheme" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "unifi";
				};
				truenas = {
					entryPoints = [ "websecure" ];
					rule = "Host(`truenas.${tr_secrets.traefik.homelab_domain}`)";
					middlewares = [ "default-headers" "https-redirectscheme" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "truenas";
				};
				octoprint = {
					entryPoints = [ "websecure" ];
					rule = "Host(`octoprint.${tr_secrets.traefik.homelab_domain}`)";
					middlewares = [ "default-headers" "https-redirectscheme" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "octoprint";
				};
				jellyfin = {
					entryPoints = [ "websecure" ];
					rule = "Host(`jellyfin.${tr_secrets.traefik.homelab_domain}`)";
					middlewares = [ "default-headers" "https-redirectscheme" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "jellyfin";
				};
				syncthing = {
					entryPoints = [ "websecure" ];
					rule = "Host(`syncthing.${tr_secrets.traefik.homelab_domain}`)";
					middlewares = [ "default-headers" "https-redirectscheme" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "syncthing";
				};
				radicale = {
					entryPoints = [ "websecure" ];
					rule = "Host(`radicale.${tr_secrets.traefik.homelab_domain}`) && PathPrefix(`/radicale`)";
					middlewares = [ "default-headers" "https-redirectscheme" "radicale-headers" "radicale-strip" ];
					tls =  {
						certResolver = "cloudflare";
					};
					service = "radicale";
				};
				traefik = {
					entryPoints = [ "websecure" ];
					rule = "Host(`traefik.${tr_secrets.traefik.homelab_domain}`) && (PathPrefix(`/api`) || PathPrefix(`/dashboard`))";
					service = "api@internal";	
				};
			};
			services = {
				# begin Services
				dashboard = {
					loadBalancer = {
						servers = [	
							{url = "http://10.1.8.129:8082";}
						];
						passHostHeader = "true";
					};
				};
				proxmox = {
					loadBalancer = {
						servers = [	
							{url = "https://10.3.29.2:8006";}
						];
						passHostHeader = "true";
					};
				};
				jellyfin = {
					loadBalancer = {
						servers = [	
							{url = "http://10.3.29.6:8096";}
						];
						passHostHeader = "true";
					};
				};
				unifi = {
					loadBalancer = {
						servers = [	
							{url = "https://10.1.8.1";}
						];
						passHostHeader = "true";
					};
				};
				truenas = {
					loadBalancer = {
						servers = [	
							{url = "https://10.1.8.4";}
						];
						passHostHeader = "true";
					};
				};
				octoprint = {
					loadBalancer = {
						servers = [	
							{url = "https://10.3.29.6:5000";}
						];
						passHostHeader = "true";
					};
				};
				syncthing = {
					loadBalancer = {
						servers = [	
							{url = "https://10.1.8.121:8384";}
						];
						passHostHeader = "true";
					};
				};
				traefik = {
					loadBalancer = {
						servers = [	
							{url = "https://10.1.8.129:8080";}
						];
						passHostHeader = "true";
					};
				};
				radicale = {
					loadBalancer = {
						servers = [	
							{url = "http://10.1.8.121:5232/";}
						];
						passHostHeader = "true";
					};
				};
			};
			 middlewares = {
				default-headers = {
					headers = {
						frameDeny = "true";
						sslRedirect = "true";
						browserXssFilter = "true";
						contentTypeNoSniff = "true";
						forceSTSHeader = "true";
						stsIncludeSubDomains = "true";
						stsPreload = "true";
						stsSeconds = "15552000";
						customFrameOptionsValue = "SAMEORIGIN";
						customRequestHeaders = {
							X-Forwarded-Proto = "https";
						};
					};
				};
				https-redirectscheme = {
					redirectScheme = {
						scheme = "https";
						permanent = "true";
					};
				};				
				radicale-headers = {
					headers = {
						customRequestHeaders = {
							X-Script-Name = "/radicale";
						};
					};
				};
				radicale-strip = {
					stripPrefix = {
						prefixes = ["/radicale"];
					};
				};
				default-whitelist = {
					ipWhiteList = {
						sourceRange = [
							"10.0.0.0/8"
							"192.168.0.0/16"
							"172.16.0.0/12"
						];
					};
				};
				secured = {
					chain = {
						middlewares = [
							"default-whitelist"
							"default-headers"
						];
					};
				};
			 };
		};
	};
}