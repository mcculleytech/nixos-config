{
  fileSystems."/home/alex/ISOs" = {
    device = "truenas.nix.mcculley.tech:/mnt/billthepony/proxmox/template/iso";
    fsType = "nfs";
    options = ["rw" "soft" ];
  };

  fileSystems."/home/alex/Documents/Games" = {
    device = "truenas.nix.mcculley.tech:/mnt/billthepony/games";
    fsType = "nfs";
    options = ["rw" "soft" ];
  };

}
