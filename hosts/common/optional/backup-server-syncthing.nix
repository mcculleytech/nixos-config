{ inputs, config, lib, ... }: {

  sops.secrets.TrueNas_syncthing_id = {
    sopsFile = ../../maul/secrets.yaml;
  };
  sops.templates."TrueNas_syncthing_id".content = ''
    "${config.sops.placeholder.TrueNas_syncthing_id}"
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
             id = "${config.sops.placeholder.TrueNas_syncthing_id}"; 
             autoAcceptFolders = true;
          };
        };
      };
    };
  };
  # Allow gui 
  networking.firewall.allowedTCPPorts = [ 8384 ];
}
