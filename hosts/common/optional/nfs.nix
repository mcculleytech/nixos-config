{

  # Only mounts when the mount point is accessed. Doesn't mount at boot.

  fileSystems."/home/alex/Documents/ISOs" = {
    device = "truenas.tail5c738.ts.net:/mnt/billthepony/proxmox/template/iso";
    fsType = "nfs";
    options = [ "rw" "soft" "noauto" "x-systemd.automount" ];
  };

  fileSystems."/home/alex/Documents/Games" = {
    device = "truenas.tail5c738.ts.net:/mnt/billthepony/games";
    fsType = "nfs";
    options = [ "rw" "soft" "noauto" "x-systemd.automount" ];
  };

}
