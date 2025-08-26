{ inputs, config, lib, pkgs, ... }:
let
  st_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_syncthing.json);
in
{
options = {
		syncthing-server.enable =
			lib.mkEnableOption "enables syncthing server functionality";
	};
	config = lib.mkIf config.syncthing-server.enable {
    environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
          "/var/lib/syncthing"
        ];
      };
    };

    services = {
      syncthing = {
        package = pkgs.unstable.syncthing;
        enable = true;
        user = "syncthing";
        openDefaultPorts = true;
        # Uncomment this line and firewall line for gui access.
        guiAddress = "0.0.0.0:8384";
        settings = {
          folders = {
            # "Logseq" = {
            #   id = "Logseq";
            #   path = "${config.services.syncthing.dataDir}/Logseq";
            #   versioning = {
            #     type = "simple";
            #     params.keep = "5";
            #   };
            #   devices = [
            #     "achilles"
            #     "aeneas"
            #     "pixel"
            #     "truenas"
            #   ];
            # };
            # "Obsidian" = {
            #   id = "Obsidian";
            #   path = "/var/lib/syncthing/Obsidian";
            #   versioning = {
            #     type = "simple";
            #     params.keep = "5";
            #   };
            #   devices = [
            #     "achilles"
            #     "aeneas"
            #     "maul"
            #     "pixel"
            #     "truenas"
            #     "mac"
            #   ];
            # };
            "Synced-Documents" = {
              id = "Synced-Documents";
              path = "/var/lib/syncthing/Synced-Documents";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "achilles"
                "aeneas"
                "maul"
                # "pixel"
                # "truenas"
                "mac"
              ];
            };
            "Pixel-Photos" = {
              id = "pixel_7_pro_rhez-photos";
              path = "/var/lib/syncthing/Camera";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "achilles"
                "aeneas"
                "maul"
                "pixel"
                # "truenas"
                "mac"
              ];
            };
          };
          devices = {
            "achilles" = {
              id = "${st_secrets.syncthing.achilles_id}";
            };
            "aeneas" = {
              id = "${st_secrets.syncthing.aeneas_id}";
            };
            "pixel" = {
              id = "${st_secrets.syncthing.pixel_id}";
            };
            "maul" = {
              id = "${st_secrets.syncthing.maul_id}";
            };
            # "truenas" = {
            #   id = "${st_secrets.syncthing.truenas_id}";
            # };
            "mac" = {
              id = "${st_secrets.syncthing.mac_id}";
            };
          };
          gui = {
            user = "${st_secrets.syncthing.syncthing_user}";
            password = "${st_secrets.syncthing.syncthing_pass}";
          };
          options = {
            localAnnounceEnabled = true;
            relaysEnabled = true;
            globalAnnounceEnabled = true;
          };
        };
        overrideFolders = true;
        overrideDevices = true;
      };
    };
    # FW Ports
    networking.firewall.allowedTCPPorts = [ 8384 22000 ];
    networking.firewall.allowedUDPPorts = [ 22000 21027 ];
	};
}
