{ config, lib, pkgs, ... }:

let 
  labelScript = ''
    #!/bin/bash

    disk="/dev/sdX"
    label="mylabel"
    
    # Check if the disk has a label
    existing_label=$(blkid -s LABEL -o value $disk)
    
    if [ -z "$existing_label" ]; then
      echo "Disk $disk does not have a label. Adding label $label..."
      tune2fs $disk -L $label
      echo "Label $label added to disk $disk."
    else
      echo "Disk $disk already has a label: $existing_label."
    fi
  '';

in 
{
  systemd.services.add-disk-label = {
    description = "Add label to disk";
    serviceConfig = {
      Type = "oneshot";
      script = labelScript;
    };
    wantedBy = [ "multi-user.target" ];  # Adjust as needed
    serviceConfig.Restart = "no";  # Prevent restarting the service
  };
}