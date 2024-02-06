{ inputs, lib, config, ... }:
{
    
  sops.defaultSopsFile = ../../../secrets/main.yaml;
  # This will automatically import SSH keys as age keys
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # This is using an age key that is expected to already be in the filesystem
  sops.age.keyFile = "/home/alex/.config/sops/age/keys.txt";
  # This will generate a new key if the key specified above does not exist
  sops.age.generateKey = true;
}

