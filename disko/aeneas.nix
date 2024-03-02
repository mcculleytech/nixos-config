{ config, lib, ... }:
{
  disko.devices = {
    disk = {
      aeneasRoot = {
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
                  # if you want to use the key for interactive login be sure there is no trailing newline
                  # for example use `echo -n "password" > /tmp/secret.key`
                  keyFile = "/tmp/secret.key";
                };
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
                    # Comment this out if you'd like to opt-in for home impermanence.
                    "/home" = {
                      mountOptions = [ "compress=zstd" ];
                      mountpoint = "/home";
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
      disk = {

      };
    };
  };
}

