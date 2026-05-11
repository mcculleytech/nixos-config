{ lib, pkgs, config, ... }:
let
  cfg = config.signal-cli;
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
      default = 8080;
      description = ''
        Local port the signal-cli HTTP daemon listens on. Loopback only;
        never opened in the firewall. Hermes connects via 127.0.0.1.
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
    environment.systemPackages = [ pkgs.signal-cli ];

    # Persist the entire signal-cli state dir across reboots — losing it
    # would mean re-linking the device.
    environment.persistence."/persist".directories = [
      { directory = cfg.dataDir; user = cfg.user; group = cfg.user; mode = "0700"; }
    ];

    systemd.tmpfiles.rules = [
      "d ${cfg.dataDir} 0700 ${cfg.user} ${cfg.user} -"
    ];

    systemd.services.signal-cli = {
      description = "signal-cli HTTP daemon (Signal protocol gateway for Hermes)";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      wantedBy = [ "multi-user.target" ];
      before = [ "hermes-agent.service" ];

      environment = {
        # signal-cli respects XDG_DATA_HOME for its state dir. Point it at
        # our persisted location.
        XDG_DATA_HOME = builtins.toString (builtins.dirOf cfg.dataDir);
      };

      serviceConfig = {
        ExecStart = "${pkgs.signal-cli}/bin/signal-cli daemon --http=127.0.0.1:${toString cfg.httpPort}";
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
  };
}
