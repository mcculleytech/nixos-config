{ config, pkgs, ... }:

{

  sops.secrets = {
    gitea_mail_pass = {
      sopsFile = ../../vader/secrets.yaml;
    };
    gitea_db_pass = {
      sopsFile = ../../vader/secrets.yaml;
    };
  }

  sops.templates.{
    "gitea_mail_pass".content = ''
      "${config.sops.placeholder.gitea_mail_pass}"
    '';
    "gitea_db_pass".content = ''
      "${config.sops.placeholder.gitea_db_pass}"
    '';
  };

  services.postgresql.enable = true;
  services.gitea = {
    enable = true;
    domain = "source.mcculley.tech";  
    allow_sign_up = true; 
    database = {
      type = "postgres"; 
      host = "localhost"; 
      name = "gitea"; 
      user = "gitea"; 
      password = "${config.sops.placeholder.gitea_db_pass}";  # Set your database password here
    };
    security = {
      INSTALL_LOCK = true; 
    };
    httpPort = 3008; 

    # Configure SMTP settings for Mailgun
    mailer = {
      ENABLED = true;
      FROM = "noreply@mcculley.tech";  # Set the "From" address for outgoing emails
      SMTP = {
        ENABLED = true;
        HOST = "smtp.mailgun.org";
        PORT = 587;
        USER = "gitea@mail.mcculley.tech";  # Your Mailgun SMTP username
        PASS = "${config.sops.placeholder.gitea_mail_pass}";  # Your Mailgun SMTP password
        STARTTLS = true;
      };
    };
  };

  # Configure SSH to use a non-standard port
  networking.firewall.allowedTCPPorts = [ 3008 2222 ];  # Open ports 3008 (HTTP) and 2222 (SSH)
  services.openssh.enable = true;
  services.openssh.listenAddresses = [
    { port = 2222; address = "0.0.0.0"; }
  ];
}
