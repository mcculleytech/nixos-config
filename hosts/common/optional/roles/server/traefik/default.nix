{ pkgs, config, lib, ... }: {

imports = [
  ./dynamic-config.nix
  ./static-config.nix
];

options = {
		traefik.enable =
			lib.mkEnableOption "enables traefik functionality";
	};

		config = lib.mkIf config.traefik.enable {

	    sops.secrets = {
	      cloudflare_email = {
	        sopsFile = ../../../../../atreides/secrets.yaml;
	      };
	      cloudflare_api_key = {
	        sopsFile = ../../../../../atreides/secrets.yaml;
	      };
	    };

	    sops.templates."traefik-cloudflare.env".content = ''
	      CF_API_EMAIL=${config.sops.placeholder.cloudflare_email}
	      CF_API_KEY=${config.sops.placeholder.cloudflare_api_key}
	    '';


		   services.traefik = {
		   	package = pkgs.unstable.traefik;
		   	enable = true;
	      dataDir = "/var/lib/traefik";
	      environmentFiles = [ config.sops.templates."traefik-cloudflare.env".path ];
		   };

        systemd.services.traefik.serviceConfig = {
          ProtectSystem = "full";
          ReadWritePaths = [ "/var/run/docker.sock" ];
        };


    users.users.traefik.extraGroups = ["docker" "acme"];

    networking.firewall.allowedTCPPorts = [ 80 443 8080 ];

	   environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
          "/var/lib/traefik"
        ];
      };
    };
	};

}
