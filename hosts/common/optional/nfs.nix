{

  # Need to figure out auto mounting via tailscale. Shelving for now.

  fileSystems."/home/alex/ISOs" = {
    device = "truenas.tail5c738.ts.net:/mnt/billthepony/proxmox/template/iso";
    fsType = "nfs";
    options = ["rw" "soft" ];
  };

  fileSystems."/home/alex/Documents/Games" = {
    device = "truenas.tail5c738.ts.net:/mnt/billthepony/games";
    fsType = "nfs";
    options = ["rw" "soft" ];
  };

}
