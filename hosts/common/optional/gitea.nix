{ config, pkgs, ... }:

{

  sops.secrets = {
    gitea_mail_pass = {
      sopsFile = ../../vader/secrets.yaml;
    };
    gitea_db_pass = {
      sopsFile = ../../vader/secrets.yaml;
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
      password = "${config.sops.placeholder.gitea_db_pass}";  # Set your database password here
    };
    appName = "McCulley Tech Gitea";
    settings = {
      server = {
        DOMAIN = "source.mcculley.tech";
        HTTP_PORT = 3008;
        PROTOCOL = "https";
        SSH_PORT = 2222;
      };
      service = {
        DISABLE_REGISTRATION = false;
      }; 

    # Configure SMTP settings for Mailgun
    mailer = {
      ENABLED = true;
      FROM = "noreply@mcculley.tech";  # Set the "From" address for outgoing emails
      SMTP_ADDR = "smtp.mailgun.org";
      SMTP_PORT = 587;
      USER = "gitea@mail.mcculley.tech";  # Your Mailgun SMTP username
      PASSWD = "${config.sops.placeholder.gitea_mail_pass}";  # Your Mailgun SMTP password
      STARTTLS = true;
    };
  };
};

  # Configure SSH to use a non-standard port
  networking.firewall.allowedTCPPorts = [ 3008 2222 ];  # Open ports 3008 (HTTP) and 2222 (SSH)
  services.openssh.enable = true;
  services.openssh.listenAddresses = [
    { port = 2222; addr = "0.0.0.0"; }
  ];
}
