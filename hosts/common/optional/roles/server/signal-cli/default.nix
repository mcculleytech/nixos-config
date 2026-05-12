{ lib, pkgs, config, ... }:
let
  cfg = config.signal-cli;
  # Wrapper that locks in the same data directory the daemon uses.
  # Without this, ad-hoc `sudo -u hermes signal-cli ...` invocations fall back
  # to the user-default `~/.local/share/signal-cli/`, which diverges from the
  # daemon's path and means newly-registered accounts don't show up over the
  # HTTP RPC. The wrapper makes the operator command path-agnostic.
  signal-cli-hermes = pkgs.writeShellScriptBin "signal-cli-hermes" ''
    exec ${pkgs.signal-cli}/bin/signal-cli --config ${cfg.dataDir} "$@"
  '';
in
{
  options.signal-cli = {
    enable = lib.mkEnableOption "signal-cli HTTP daemon for Hermes Signal bot";

    user = lib.mkOption {
      type = lib.types.str;
      default = "hermes";
      description = ''
        UNIX user that owns signal-cli state and runs the daemon. Created
        by the upstream hermes-agent NixOS module — we only depend on it
        (and order ourselves before hermes-agent.service).
      '';
    };

    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8088;
      description = ''
        Local port the signal-cli HTTP daemon listens on. Loopback only;
        never opened in the firewall. Hermes connects via 127.0.0.1.
        Default 8088 (not 8080) — open-webui already binds 8080 on saruman.
      '';
    };

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/var/lib/hermes/signal-cli";
      description = ''
        Where signal-cli stores its linked-device key state, contacts,
        sessions, and message cache. Persisted under /persist via
        impermanence so the link survives reboots.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.signal-cli signal-cli-hermes ];

    # Persist the entire signal-cli state dir across reboots — losing it
    # would mean re-linking the device.
    environment.persistence."/persist".directories = [
      { directory = cfg.dataDir; user = cfg.user; group = cfg.user; mode = "0700"; }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 ${cfg.user} ${cfg.user} -"
      # Backup landing zone — root-only; signal-cli state is sensitive
      # (linked-device protobuf, axolotl session keys, identity).
      "d /persist/backups 0755 root root -"
      "d /persist/backups/signal-cli 0700 root root -"
    ];

    systemd.services.signal-cli = {
      description = "signal-cli HTTP daemon (Signal protocol gateway for Hermes)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "hermes-agent.service" ];

      # Data dir is set explicitly via `--config` rather than XDG_DATA_HOME.
      # This means operators using `signal-cli` directly (without our wrapper)
      # won't accidentally write account state to ~/.local/share/signal-cli/
      # and surprise the daemon. Use the `signal-cli-hermes` wrapper on PATH
      # for any interactive admin commands.

      serviceConfig = {
        ExecStart = "${pkgs.signal-cli}/bin/signal-cli --config ${cfg.dataDir} daemon --http=127.0.0.1:${toString cfg.httpPort}";
        User = cfg.user;
        Group = cfg.user;
        Restart = "always";
        RestartSec = "5s";

        # Hardening; service needs read+write on its data dir only.
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.dataDir ];
      };
    };

    # No firewall opening: loopback-only by design.

    # ─── Weekly tarball of signal-cli state ────────────────────────────────
    # Linked-device protobuf, axolotl session keys, identity, contacts —
    # losing this dir means re-linking the bot from the phone. Daily would
    # be overkill (state churns slowly); weekly is the sweet spot.
    #
    # Hot read (no service stop): signal-cli writes are atomic file replaces,
    # so a tar pass captures "either old or new" per file — no torn writes.
    # Stopping the daemon during backup would be more bulletproof but costs
    # a weekly outage window; not worth it for slow-churn state.
    systemd.services.signal-cli-backup = {
      description = "Weekly tarball of signal-cli state directory";
      after = [ "signal-cli.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "root";
        Group = "root";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/persist/backups/signal-cli" ];
      };
      script = ''
        set -eu
        ts=$(${pkgs.coreutils}/bin/date -u +%Y-%m-%d)
        out=/persist/backups/signal-cli/signal-cli-$ts.tar.gz
        ${pkgs.gnutar}/bin/tar -czf "$out.tmp" \
          -C "$(${pkgs.coreutils}/bin/dirname ${cfg.dataDir})" \
          "$(${pkgs.coreutils}/bin/basename ${cfg.dataDir})"
        ${pkgs.coreutils}/bin/mv "$out.tmp" "$out"
        ${pkgs.findutils}/bin/find /persist/backups/signal-cli \
          -name 'signal-cli-*.tar.gz' -mtime +56 -delete
      '';
    };

    systemd.timers.signal-cli-backup = {
      description = "Weekly timer for signal-cli state tarball";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "Sun 04:00";
        Persistent = true;
        RandomizedDelaySec = "10m";
      };
    };
  };
}
