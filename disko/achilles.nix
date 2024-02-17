{ config, lib, ... }:
{
  disko.devices = {
    disk = {
      achillesRoot = {
        type = "disk";
        device = "/dev/nvme0n1";
        content = {
          type = "gpt";
          partitions = {
            boot = {
              size = "1M";
              type = "EF02"; # for grub MBR
              label = "boot";
            };
            ESP = {
              size = "512M";
              type = "EF00";
              label = "ESP";
              content = {
                extraArgs = [ "-n ESP" ];
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            luks = {
              size = "100%";
              content = {
                type = "luks";
                name = "encryptedRoot";
                settings = {
                  allowDiscards = true;
                  # usb unencrypt
                  # keyFile = "/dev/disk/by-id/usb-SMI_USB_DISK-0:0";
                  # keyFileSize = 4096;
                  keyFile = "/tmp/secret.key";
                };
                additionalKeyFiles = [ "/dev/disk/by-id/usb-SMI_USB_DISK-0:0" ];
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
                      mountOptions = [ "compress=zstd" ];
                      mountpoint = "/";
                    };
                    "/persist" = {
                      mountOptions = [ "compress=zstd" ];
                      mountpoint = "/persist";
                    };
                    "/nix" = {
                      mountOptions = [ "compress=zstd" "noatime" ];
                      mountpoint = "/nix";
                    };
                    "/swap" = {
                      mountpoint = "/.swapvol";
                      swap = {
                        swapfile.size = "8G";
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
        achillesHome = {
          type = "disk";
          device = "/dev/sda";
          content = {
            type = "gpt";
            partitions = {
              luks = {
                size = "100%";
                content = {
                  type = "luks";
                  name = "encryptedHome";
                settings = {
                  allowDiscards = true;
                  # usb unencrypt
                  # keyFile = "/dev/disk/by-id/usb-SMI_USB_DISK-0:0";
                  # keyFileSize = 4096;
                  keyFile = "/tmp/secret.key";
                };
                additionalKeyFiles = [ "/dev/disk/by-id/usb-SMI_USB_DISK-0:0" ];
                # interactive password for unencypting
                  content = {
                    type = "btrfs";
                    extraArgs = [ "-f" ];
                    subvolumes = {
                      "/home" = {
                        mountpoint = "/home";
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

