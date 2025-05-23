{ config, pkgs, lib, ... }:
let
  gitea_secrets = builtins.fromJSON (builtins.readFile ../../../../../../secrets/git_crypt_gitea.json);
in
# This configuration disables registration, but you can use the gitea cli to add a user.
{

 	options = {
		gitea.enable =
			lib.mkEnableOption "enables gitea";
	};
	config = lib.mkIf config.gitea.enable {

    sops.secrets = {
      gitea_mail_pass = {
        sopsFile = ../../../../../vader/secrets.yaml;
        owner = config.systemd.services.gitea.serviceConfig.User;
      };
      gitea_db_pass = {
        sopsFile = ../../../../../vader/secrets.yaml;
        owner = config.systemd.services.gitea.serviceConfig.User;
      };
    };

    sops.templates."gitea_mail_pass".content = ''
        "${config.sops.placeholder.gitea_mail_pass}"
      '';

    sops.templates."gitea_db_pass".content = ''
        "${config.sops.placeholder.gitea_db_pass}"
      '';

    services.postgresql.enable = true;
    services.gitea = {
      enable = true;
      database = {
        type = "postgres";
        host = "localhost";
        name = "gitea";
        user = "gitea";
        passwordFile = config.sops.secrets.gitea_db_pass.path;
      };
      appName = "McCulley Tech Gitea";
      settings = {
        server = {
          DOMAIN = "${gitea_secrets.gitea.domain}";
          ROOT_URL = "${gitea_secrets.gitea.url}";
          HTTP_PORT = 3008;
          PROTOCOL = "http";
          SSH_PORT = 22;
        };
        ui = {
          SHOW_USER_EMAIL = false;
        };
        service = {
          DISABLE_REGISTRATION = true;
        };
        mailer = {
          ENABLED = true;
          PROTOCOL = "smtp+starttls";
          FROM = "noreply@mcculley.tech";
          SMTP_ADDR = "smtp.mailgun.org";
          SMTP_PORT = 587;
          USER = "gitea@mail.mcculley.tech";
        };
        actions = {
          ENABLED = true;
        };
      };
      mailerPasswordFile = config.sops.secrets.gitea_mail_pass.path;
      customDir = "${config.services.gitea.stateDir}/custom";
};


    # Persist storage across reboots
    environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
          "/var/lib/gitea"
          "/var/lib/postgresql"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ 3008 ];  # Open ports 3008 (HTTP)
	};
}
