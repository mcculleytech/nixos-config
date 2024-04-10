{ config, lib, ... }: 
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
                  extraArgs = [ "-f" "-L ${config.networking.hostName}" ]; # Override existing partition
                  postCreateHook = /* sh */ ''
                      MNTPOINT=$(mktemp -d)
                      mount "/dev/disk/by-label/${config.networking.hostName}" "$MNTPOINT" -o subvol=/
                      trap 'umount $MNTPOINT; rm -rf $MNTPOINT' EXIT
                      btrfs subvolume snapshot -r $MNTPOINT/root $MNTPOINT/root-blank
                    '';
                  subvolumes = {
                    "/root" = {
                      mountpoint = "/";
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
                    "/swap" = {
                      mountpoint = "/.swapvol";
                      swap = {
                        swapfile.size = "4G";
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
    disk = {
      sdb = {
        type = "disk";
        # Backup disk needs to be entered below
        device = "/dev/sdc";
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
                  extraArgs = [ "-f" "-L ${config.networking.hostName}-data" ]; # Override existing partition
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

