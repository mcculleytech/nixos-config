{ lib, pkgs, config, ... }:
let
  cfg = config.obsidian-headless;
in
{
  options.obsidian-headless = {
    enable = lib.mkEnableOption "Obsidian Sync headless daemon (proprietary, requires a paid Obsidian Sync subscription)";

    user = lib.mkOption {
      type = lib.types.str;
      default = "alex";
      description = ''
        UNIX user that owns the vault and runs the sync daemon. The user's
        Obsidian Sync credentials live at $XDG_CONFIG_HOME/obsidian-headless/.
        First-time setup is interactive: ssh in as this user and run
        `ob login` once. The daemon won't start successfully until that file
        exists.
      '';
    };

    vaultPath = lib.mkOption {
      type = lib.types.path;
      default = "/home/alex/obsidian/Barrow-Downs";
      description = "Absolute path to the on-disk vault directory the daemon keeps in sync.";
    };

    configDir = lib.mkOption {
      type = lib.types.path;
      default = "/home/alex/.config/obsidian-headless";
      description = ''
        Where `ob` reads/writes its session token and per-vault state. On the
        chosen user's /home (which is its own btrfs subvol on saruman), so
        this naturally survives reboots without an impermanence rule.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # Make `ob` available in the user's shell so they can run `ob login`,
    # `ob sync-status`, etc. manually.
    environment.systemPackages = [ pkgs.obsidian-headless ];

    systemd.services.obsidian-headless = {
      description = "Obsidian Sync headless daemon (continuous sync)";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      # Only attempt to run if the user has completed the interactive
      # `ob login` flow. Prevents a tight crash loop before bootstrap.
      unitConfig.ConditionPathExists = "${cfg.configDir}";

      environment = {
        # XDG_CONFIG_HOME drives where `ob` looks for its session/state.
        XDG_CONFIG_HOME = builtins.toString (builtins.dirOf cfg.configDir);
      };

      serviceConfig = {
        ExecStart = "${pkgs.obsidian-headless}/bin/ob sync --continuous --path ${cfg.vaultPath}";
        User = cfg.user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = "10s";

        # Modest hardening — service needs to write to the vault dir and the
        # config dir, both under /home.
        ProtectSystem = "strict";
        ProtectHome = false; # we WANT access to /home/<user>/...
        NoNewPrivileges = true;
        PrivateTmp = true;
        ReadWritePaths = [ cfg.vaultPath cfg.configDir ];
      };
    };

    # Watchdog. obsidian-headless can hang in a half-open reconnect state
    # after a brief network drop — the process stays alive (so Restart=
    # never fires) but stops syncing entirely. Seen 2026-06-04: a ~20s WAN
    # blip wedged it for 2.5 days, silently, until a manual restart. A
    # healthy daemon logs ("Fully synced" / "Downloading…" / etc.) roughly
    # every 30s; a wedged one goes completely silent. So: if the unit is
    # active but has produced no journal output for 10 minutes, it's stuck —
    # bounce it. Restarting re-establishes the connection and flushes the
    # backlog.
    systemd.services.obsidian-headless-watchdog = {
      description = "Restart obsidian-headless if it has stopped syncing";
      path = [ pkgs.systemd ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
      };
      script = ''
        if ! systemctl is-active --quiet obsidian-headless.service; then
          # Not running — its own Restart=/ConditionPathExists govern this.
          exit 0
        fi
        recent=$(journalctl -u obsidian-headless.service --since "10 min ago" \
                   --no-pager -o cat -q || true)
        if [ -z "$recent" ]; then
          echo "obsidian-headless: no log output in 10m while active — wedged, restarting"
          systemctl restart obsidian-headless.service
        else
          echo "obsidian-headless: healthy (logged within last 10m)"
        fi
      '';
    };

    systemd.timers.obsidian-headless-watchdog = {
      description = "Periodic liveness check for obsidian-headless sync";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "10min";
        OnUnitActiveSec = "5min";
        RandomizedDelaySec = "30s";
      };
    };
  };
}
