{config, lib, ... }:
let
  hasOptinPersistence = config.environment.persistence ? "/persist";
in
{
  services.openssh = {
    enable = true;
    settings = {
      # Need to allow root login for remote builds. Potential fix in Colmena, possibly with pam sshagentauth
      PermitRootLogin = "yes";
      PasswordAuthentication = false;
    };
    # Commit to persistance with this.
    hostKeys = [{
      path = "${lib.optionalString hasOptinPersistence "/persist"}/etc/ssh/ssh_host_ed25519_key";
      type = "ed25519";
    }];
  };

  # Passwordless sudo login
  # security.pam.enableSSHAgentAuth = true;
}
