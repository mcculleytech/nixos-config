{config, ... }: 
{

  sops.secrets.syncthing_server_id = {
    sopsFile = ../../../../../secrets/main.yaml;
  };

  sops.templates."syncthing_server_id".content = ''
    "${config.sops.placeholder.syncthing_server_id}"
  '';

# One day I'll move to totally using nix and this will be cleaner
  services = {
    syncthing = {
      enable = true;
      user = "alex";
      configDir = "/home/alex/.config/syncthing";
      settings = {
        devices = {
          TrueNAS = {
            name = "TrueNAS";
            id = "${config.sops.placeholder.syncthing_server_id}";
            autoAcceptFolders = true;
             };
        };
      };
      overrideDevices = false;
      overrideFolders = false;
    };
  };
}