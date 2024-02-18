  { config, ... }: {

  sops.secrets.nfs_hash = {
    sopsFile = ../../maul/secrets.yaml;
    neededForUsers = true;
  };

  # Create NFS user for clients to connect to endpoints with
  users.users.nfs = {
    uid = 1002;
    group = "nfs";
    isNormalUser = true;
    hashedPasswordFile = config.sops.secrets.nfs_hash.path;
  };

  users.groups.nfs = {
    gid = 1002;
  };
  

  systemd.tmpfiles.rules = [
    "d /data/proxmox 0755 nfs nfs -"
  ];


  # Firewall setup
  services.nfs.server = {
    enable = true;
    # fixed rpc.statd port; for firewall
    lockdPort = 4001;
    mountdPort = 4002;
    statdPort = 4000;
    extraNfsdConfig = '''';
    exports = ''
      # Should use DNS names in final revision
      /data/proxmox        gandalf.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
      /data/proxmox        pippin.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
      /data/proxmox        sam.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
      /data/proxmox        achilles.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
      /data/proxmox        aeneas.tail5c738.ts.net(rw,sync,all_squash,anonuid=1002,anongid=1002,no_subtree_check)
    '';
  };
  networking.firewall = {
    enable = true;
      # for NFSv3; view with `rpcinfo -p`
    allowedTCPPorts = [ 111  2049 4000 4001 4002 20048 ];
    allowedUDPPorts = [ 111 2049 4000 4001  4002 20048 ];
  };
}
