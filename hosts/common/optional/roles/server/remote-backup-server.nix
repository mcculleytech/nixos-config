{ inputs, config, lib, pkgs, ... }:
let
  st_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_syncthing.json);
in
{

  options = {
		remote-backup-server.enable =
			lib.mkEnableOption "enables remote backup server functionality";
	};
	config = lib.mkIf config.remote-backup-server.enable {

    systemd.tmpfiles.rules = [
      "d /data/syncthing 0755 syncthing syncthing -"
      "d /data/proxmox 0755 nfs nfs -"
    ];


    services = {
      syncthing = {
        package = pkgs.unstable.syncthing;
        enable = true;
        user = "syncthing";
        dataDir = "/data/syncthing";
        openDefaultPorts = true;
        # Uncomment this line and firewall line for gui access.
        guiAddress = "0.0.0.0:8384";
        settings = {
          folders = {
            "Logseq" = {
              id = "Logseq";
              path = "${config.services.syncthing.dataDir}/Logseq";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "achilles"
                "aeneas"
                "phantom"
                "pixel"
                "truenas"
              ];
            };
            "Obsidian" = {
              id = "Obsidian";
              path = "${config.services.syncthing.dataDir}/Obsidian";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "achilles"
                "aeneas"
                "phantom"
                "pixel"
                "truenas"
              ];
            };
            "Synced-Documents" = {
              id = "Synced-Documents";
              path = "${config.services.syncthing.dataDir}/Synced-Documents";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "achilles"
                "aeneas"
                "phantom"
                "pixel"
                "truenas"
              ];
            };
            "Pixel-Photos" = {
              id = "pixel_7_pro_rhez-photos";
              path = "${config.services.syncthing.dataDir}/Camera";
              versioning = {
                type = "simple";
                params.keep = "5";
              };
              devices = [
                "achilles"
                "aeneas"
                "phantom"
                "pixel"
                "truenas"
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
            "phantom" = {
              id = "${st_secrets.syncthing.phantom_id}";
            };
            "truenas" = {
              id = "${st_secrets.syncthing.truenas_id}";
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


    # nfs server
    sops.secrets.nfs_hash = {
      sopsFile = ../../../../maul/secrets.yaml;
      neededForUsers = true;
    };

    # Create NFS user for clients to connect to endpoints with
    users.users.nfs = {
      uid = 1002;
      group = "nfs";
      isNormalUser = true;
      hashedPasswordFile = config.sops.secrets.nfs_hash.path;
    };

    users.groups.nfs = {
      gid = 1002;
    };

    # Configure nfs-server to start only after boot so it recognizes the tailscale dns names
    # systemd.services.nfs-server = {
    #   unitConfig = {
    #     after = [ "multi-user.target" ];
    #     requires = [ "tailscaled.service" ];
    #   };
    #   serviceConfig = {
    #     # Tailscale DNS makes me do this. Service needs to be restarted once it starts
    #     execStartPost = "${pkgs.systemd}/bin/systemctl restart nfs-server";
    #   };
    # };

    systemd.services.restart-nfs-server = {
      enable = true;
      description = "Allows for Tailscale DNS in NFS Server";
      after = ["nfs-server.service"];
      wantedBy = [ "multi-user.target" ];

      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };

      script = with pkgs; ''
        ${pkgs.coreutils}/bin/sleep 30

        ${pkgs.systemd}/bin/systemctl restart nfs-server
      '';
    };

    # nfs server setup
    services.nfs.server = {
      enable = true;
      # fixed rpc.statd port; for firewall
      lockdPort = 4001;
      mountdPort = 4002;
      statdPort = 4000;
      extraNfsdConfig = '''';
      exports = ''
        # Should use DNS names in final revision
        /data/proxmox        aragorn.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
        /data/proxmox        achilles.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
        /data/proxmox        aeneas.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
      '';
    };
    networking.firewall = {
      enable = true;
        # for NFSv3; view with `rpcinfo -p` 8384 and 22000 are for syncthing, rest is nfs
      allowedTCPPorts = [ 111  2049 4000 4001 4002 20048 8384 22000 ];
      allowedUDPPorts = [ 111 2049 4000 4001  4002 20048 8384 22000 ];
    };

	};
}
