{

  services.rpcbind.enable = true; # needed for NFS
  systemd.mounts = let commonMountOptions = {
    type = "nfs";
    mountConfig = {
      Options = "noatime";
    };
  };

  in

  [
    (commonMountOptions // {
      what = "truenas.tail5c738.ts.net:/mnt/billthepony/proxmox/template/iso";
      where = "/home/alex/Documents/ISOs";
    })

    (commonMountOptions // {
      what = "truenas.tail5c738.ts.net:/mnt/billthepony/games";
      where = "/home/alex/Documents/Games";
    })
  ];

  systemd.automounts = let commonAutoMountOptions = {
    wantedBy = [ "multi-user.target" ];
    automountConfig = {
      TimeoutIdleSec = "600";
    };
  };

  in

  [
    (commonAutoMountOptions // { where = "/home/alex/Documents/ISOs"; })
    (commonAutoMountOptions // { where = "/home/alex/Documents/Games"; })
  ];

}
