{config, ... }: 
{

sops.secrets.syncthing_server_id = {
  sopsFile = ../../../secrets/main.yaml;
};

  sops.templates."syncthing_server_id".content = ''
    "${config.sops.placeholder.syncthing_server_id}"
  '';

services = {
  syncthing = {
    enable = true;
    user = "alex";
    configDir = "/home/alex/.config/syncthing";
    settings = {
      devices = {
        "Truenas" = { 
          id = "${config.sops.placeholder.syncthing_server_id}";
          autoAcceptFolders = true;
           };
      };
    };
  };
};
}