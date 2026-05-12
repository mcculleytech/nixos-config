{ lib, pkgs, config, ... }:
let
  cfg = config.obsidian-backup;
in
{
  options.obsidian-backup = {
    enable = lib.mkEnableOption "daily rsync of Obsidian vault dir to NAS";

    source = lib.mkOption {
      type = lib.types.path;
      default = "/home/alex/obsidian";
      description = ''
        Parent directory of one or more vaults. The whole subtree is mirrored
        to the NAS so future vaults under here get backed up automatically.
      '';
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "*-*-* 04:00:00";
      description = ''
        systemd OnCalendar spec. Default 04:00 UTC, after agent-memory (03:00)
        and immich (03:30) backups so the NAS doesn't see three concurrent jobs.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # rsync reads the vault and writes to the NAS — Obsidian's filesystem
    # watcher only fires on writes to /home/alex/obsidian, which never happen
    # here. So this is fully non-disruptive to Obsidian Sync; vault contents
    # remain untouched.
    systemd.services.obsidian-backup = {
      description = "Daily rsync of Obsidian vault → NAS";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      unitConfig = {
        RequiresMountsFor = [ config.lab.nas-backups.mountPath ];
      };
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        # Hardening — readonly mount on /home means even a compromised
        # rsync binary can't corrupt the vault, only the NAS-side mirror.
        ProtectSystem = "strict";
        ProtectHome = "read-only";
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ config.lab.nas-backups.mountPath ];
      };
      path = with pkgs; [ rsync coreutils ];
      script = ''
        set -eu
        dst=${config.lab.nas-backups.mountPath}/saruman/obsidian
        install -d -m 0750 -o backup -g backup "$dst"

        # -rlptD instead of -a: skip owner/group preservation so files land
        # as the writer (root → mapped to backup UID 34 by NFS maproot)
        # instead of trying to preserve UID 1000 across an NFS server that
        # doesn't know that UID.
        #
        # Excludes:
        #   workspace*.json        — Obsidian editor session state (open tabs,
        #                            cursor position); changes constantly,
        #                            useless for recovery.
        #   .obsidian/cache/       — derived index/render cache, regenerable.
        #   .trash/                — Obsidian's local trash window; older
        #                            snapshots already capture the original.
        rsync -rlptD --delete --quiet --info=stats2 \
          --exclude='workspace.json' \
          --exclude='workspace-mobile.json' \
          --exclude='workspaces.json' \
          --exclude='.obsidian/cache/' \
          --exclude='.trash/' \
          ${cfg.source}/ "$dst/"
      '';
    };

    systemd.timers.obsidian-backup = {
      description = "Daily timer for Obsidian vault rsync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };
  };
}
