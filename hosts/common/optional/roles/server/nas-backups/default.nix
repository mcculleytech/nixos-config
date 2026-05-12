{ lib, config, ... }:
let
  cfg = config.lab.nas-backups;
in
{
  options.lab.nas-backups = {
    enable = lib.mkEnableOption "NFS-mounted off-host backup share on the homelab NAS";

    nasHost = lib.mkOption {
      type = lib.types.str;
      default = "10.1.8.4";
      description = "IP or hostname of the TrueNAS server exporting the backup share.";
    };

    exportPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/billthepony/backups";
      description = "Path of the export on the NAS side.";
    };

    mountPath = lib.mkOption {
      type = lib.types.str;
      default = "/mnt/nas-backups";
      description = ''
        Local mount path. Other backup modules should reference
        config.lab.nas-backups.mountPath rather than hardcoding /mnt/nas-backups.
      '';
    };

    uid = lib.mkOption {
      type = lib.types.int;
      default = 34;
      description = ''
        UID/GID for the local `backup` user. Defaults to 34, the LSB-standard
        `backup` UID. Must match whatever UID the NAS-side `backup` user owns
        the export with (TrueNAS uses 34 by default; if you ever change it on
        either side, change it on both).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Local `backup` user/group matched to the NAS-side ownership of the
    # export. The NFS server squashes incoming UID 0 to the export owner
    # (maproot=backup on TrueNAS), so backup units can run as root and
    # still see backup-owned files when reading back from NAS — but a
    # local user keeps file ownership coherent for any local staging
    # paths and makes ls output match across saruman and the NAS.
    users.users.backup = {
      isSystemUser = true;
      uid = cfg.uid;
      group = "backup";
      home = "/var/empty";
      shell = "/run/current-system/sw/bin/nologin";
      description = "Off-host backup writer (NAS share owner)";
    };
    users.groups.backup = {
      gid = cfg.uid;
    };

    # Auto-mount on first access so the host doesn't block boot if the NAS
    # is unreachable. nfsv4.2 matches the existing immich media mount.
    fileSystems."${cfg.mountPath}" = {
      device = "${cfg.nasHost}:${cfg.exportPath}";
      fsType = "nfs4";
      options = [
        "noatime"
        "vers=4.2"
        "rsize=1048576"
        "wsize=1048576"
        "hard"
        "_netdev"
        "x-systemd.automount"
        "x-systemd.idle-timeout=600"
        "x-systemd.mount-timeout=20"
      ];
    };
  };
}
