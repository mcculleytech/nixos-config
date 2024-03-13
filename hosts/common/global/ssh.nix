{config, lib, outputs, ... }:
let
  
  inherit (config.networking) hostName;
  hasOptinPersistence = config.environment.persistence ? "/persist";
  hosts = outputs.nixosConfigurations;
  pubKey = host: ../../${host}/ssh_host_ed25519_key.pub;

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
