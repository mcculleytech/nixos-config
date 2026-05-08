{ config, lib, pkgs, ... }:

let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../../secrets/git_crypt_traefik.json);
in
{
	config = lib.mkIf config.traefik.enable {
	   services.traefik.staticConfigOptions = {
        		api = {
        			dashboard = true;
        		};
        		log.level = "DEBUG";
        		entryPoints = {
        			web = {
        				address = ":80";
        				http.redirections.entrypoint = {
        					to = "websecure";
        					scheme = "https";
        				};
        			};
        			websecure = {
        				address = ":443";
        			};
        			traefik = {
        				address = ":8080";
        			};
        			gitea-ssh = {
        				address = ":2222";
        			};
        		};
        		metrics.prometheus = {
       			entryPoint = "traefik";
       		};
       		serversTransport.insecureSkipVerify = true;
        		providers = {
        			docker = {
        				endpoint = "unix:///var/run/docker.sock";
        				exposedByDefault = false;
        			};
        		};
        		certificatesResolvers = {
        			cloudflare = {
        				acme ={
        					email = "${tr_secrets.traefik.cloudflare_email}";
        					storage = "/var/lib/traefik/acme.json";
        					dnsChallenge = {
        						provider = "cloudflare";
        						resolvers = [ "1.1.1.1:53" "1.0.0.1:53" ];
        					};
        				};
        		};
	   };

	   };
	};
}
