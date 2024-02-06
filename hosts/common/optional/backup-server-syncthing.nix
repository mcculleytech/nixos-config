{ inputs, config, lib, ... }: {

  sops.secrets.TrueNas_syncthing_id = {
    sopsFile = ../../../secrets/main.yaml;
  };
  sops.templates."syncthing_server_id".content = ''
    "${config.sops.placeholder.syncthing_server_id}"
    '';


  systemd.tmpfiles.rules = [
    "d /data/syncthing 0755 syncthing syncthing -"
  ];

  services = {
    syncthing = {
      enable = true;
      dataDir = "/data/syncthing";
      configDir = "/data/syncthing/.config/syncthing/";
      openDefaultPorts = true;
      # Uncomment this line and firewall line for gui access.
      guiAddress = "0.0.0.0:8384";
      settings = {
        devices = {
          "TrueNAS" = { 
             id = "${config.sops.placeholder.syncthing_server_id}"; 
             autoAcceptFolders = true;
          };
        };
      };
    };
  };
  # Allow gui 
  networking.firewall.allowedTCPPorts = [ 8384 ];
}
