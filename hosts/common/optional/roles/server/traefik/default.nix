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


	   services.traefik = {
	   	package = pkgs.unstable.traefik;
	   	enable = true;
      dataDir = "/var/lib/traefik";
      environmentFiles = [ config.sops.secrets.cloudflare_email.path config.sops.secrets.cloudflare_api_key.path  ];
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
