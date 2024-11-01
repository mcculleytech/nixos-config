{ pkgs, config, lib, ... }: {

    options = {
		radicale.enable =
			lib.mkEnableOption "enables radicale server";
	};

	config = lib.mkIf config.radicale.enable {

	sops.secrets = {
	  radicale_users = {
	    sopsFile = ../../../../phantom/secrets.yaml;
	    owner = config.systemd.services.radicale.serviceConfig.User;
	  };
	};

	services.radicale = {
		package = pkgs.unstable.radicale;
		enable = true;
		settings = {
			server = {
			  hosts = [ "0.0.0.0:5232" ];
			};
			auth = {
				# type = "http_x_remote_user";
				type = "htpasswd";
				htpasswd_filename = config.sops.secrets.radicale_users.path;
				htpasswd_encryption = "bcrypt";
			};
			storage ={
				filesystem_folder =	"/var/lib/radicale/collections";
			};
			logging = {
				level = "debug";
			};
		};
		rights = {
			root = {
			  user = ".+";
			  collection = "";
			  permissions = "R";
			};
			principal = {
			  user = ".+";
			  collection = "{user}";
			  permissions = "RW";
			};
			calendars = {
			  user = ".+";
			  collection = "{user}/[^/]+";
			  permissions = "rw";
			};
		};
	};

	networking.firewall.allowedTCPPorts = [ 5232 ];

	environment.persistence = {
	  "/persist" = {
	  hideMounts = true;
	    directories = [
	      "/var/lib/radicale"
	    ];
	    files = [
	      "/etc/radicale/users"
	    ];
	  };
	};
	};
}
