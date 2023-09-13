{
  fileSystems."/home/alex/ISOs" = {
    # mounted with tailscale DNS name
    device = "100.80.253.105:/mnt/billthepony/proxmox/template/iso";
    fsType = "nfs";
    options = ["rw" "soft" ];
  };

  fileSystems."/home/alex/Documents/Games" = {
    device = "100.80.253.105:/mnt/billthepony/games";
    fsType = "nfs";
    options = ["rw" "soft" ];
  };

}
