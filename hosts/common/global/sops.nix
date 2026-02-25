{ inputs, lib, config, ... }:
let
  isEd25519 = k: k.type == "ed25519";
  getKeyPath = k: k.path;
  keys = builtins.filter isEd25519 config.services.openssh.hostKeys;
in
{
    
  sops.defaultSopsFile = ../../../secrets/main.yaml;

  sops = {
    age = { 
      sshKeyPaths = map getKeyPath keys;
      # Read directly from the persisted path so key access doesn't depend on
      # impermanence bind-mount timing for /var/lib/sops-nix.
      keyFile = "/persist/var/lib/sops-nix/key.txt";
      generateKey = true;
    };
  };

}
