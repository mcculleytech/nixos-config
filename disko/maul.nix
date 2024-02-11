{
  disko.devices = {
    disk = {
      sda = {
        type = "disk";
        # OS disk
        device = "/dev/sda";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              size = "512M";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
                mountOptions = [
                  "defaults"
                ];
              };
            };
            OSluks = {
              size = "100%";
              content = {
                type = "luks";
                name = "OScrypted";
                extraOpenArgs = [ ];
                # if you want to use the key for interactive login be sure there is no trailing newline
                # for example use `echo -n "password" > /tmp/secret.key`
                #passwordFile = "/tmp/secret.key"; # Interactive
                settings = { 
		  allowDiscards = true;
                  keyFile = "/dev/disk/by-id/usb-General_UDisk_2307111809272950543702-0:0";
		  keyFileSize = 4096;
		};
                # additionalKeyFiles = [ "/tmp/additionalSecret.key" ];
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "/home" = {
                      mountpoint = "/home";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                    "/nix" = {
                      mountpoint = "/nix";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
		    "/persist" = {
		      mountpoint = "/persist";
		      mountOptions = [ "compress=zstd" "noatime" ];
		    };
                  };
                };
              };
            };
          };
        };
      };
    };
    disk = {
      sdb = {
        type = "disk";
        # Backup disk needs to be entered below
        device = "/dev/sdb";
        content = {
          type = "gpt";
          partitions = {
            NFSluks = {
              size = "100%";
              content = {
                type = "luks";
                name = "NFScrypted";
                extraOpenArgs = [ ];
                # if you want to use the key for interactive login be sure there is no trailing newline
                # for example use `echo -n "password" > /tmp/secret.key`
                #passwordFile = "/tmp/secret.key"; # Interactive
                settings = {
                  allowDiscards = true;
                  keyFile = "/dev/disk/by-id/usb-General_UDisk_2307111809272950543702-0:0";
                  keyFileSize = 4096;
                };
                # additionalKeyFiles = [ "/tmp/additionalSecret.key" ];
                content = {
                  type = "btrfs";
                  extraArgs = [ "-f" ];
                  subvolumes = {
                    "/data" = {
                      mountpoint = "/data";
                      mountOptions = [ "compress=zstd" "noatime" ];
                    };
                  };
                };
              };
            };
          };
        };
      };
    };
  };
}

