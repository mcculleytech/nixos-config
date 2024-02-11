{ config, pkgs, ... }:

{
# A work in progress. Decided to shelve this project for the time being (2-10-24)
  sops.secrets = {
    gitea_mail_pass = {
      sopsFile = ../../vader/secrets.yaml;
      owner = config.systemd.services.gitea.serviceConfig.User;
    };
    gitea_db_pass = {
      sopsFile = ../../vader/secrets.yaml;
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
      passwordFile = config.sops.secrets.gitea_db_pass.path;  # Set your database password here
    };
    appName = "McCulley Tech Gitea";
    settings = {
      server = {
        DOMAIN = "source.mcculley.tech";
        ROOT_URL = "https://source.mcculley.tech";
        HTTP_PORT = 3008;
        PROTOCOL = "http";
        SSH_PORT = 2222;
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

  # Configure SSH to use a non-standard port
  networking.firewall.allowedTCPPorts = [ 3008 2222 ];  # Open ports 3008 (HTTP) and 2222 (SSH)
  services.openssh.enable = true;
  services.openssh.listenAddresses = [
    { port = 2222; addr = "0.0.0.0"; }
  ];
}
