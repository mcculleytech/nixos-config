{
  services.openssh = {
    enable = true;
    settings = {
      # Need to allow root login for remote builds. Potential fix in Colmena
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
  };
}
