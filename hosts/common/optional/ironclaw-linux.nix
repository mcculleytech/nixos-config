{ lib, config, pkgs, ... }:
let
  cfg = config.lab.ironclaw;
  sc = config.lab.signalChannel;
  db = config.lab.ironclaw.database;
in
{
  options.lab.ironclaw.runDaemon = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Start ironclaw as a systemd service. Keep false until `ironclaw onboard`
      has been completed interactively as the service user.
    '';
  };

  options.lab.ironclaw.database = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Provision a local PostgreSQL 17 instance with pgvector for ironclaw.
        Set to false to supply your own DATABASE_URL via the ironclaw config.
      '';
    };
    name = lib.mkOption {
      type = lib.types.str;
      default = "ironclaw";
    };
    user = lib.mkOption {
      type = lib.types.str;
      default = "alex";
      description = ''
        PostgreSQL role name. Must match the OS user that runs ironclaw so peer
        auth works without a password.
      '';
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    # ── package + signal-cli ────────────────────────────────────────────
    {
      environment.systemPackages =
        lib.optional (!cfg.fromBrew) pkgs.ironclaw
        ++ lib.optional sc.enable pkgs.signal-cli;

      environment.variables = lib.optionalAttrs sc.enable {
        SIGNAL_HTTP_URL = "http://127.0.0.1:${toString sc.httpPort}";
      };
    }

    # ── PostgreSQL + pgvector ───────────────────────────────────────────
    (lib.mkIf db.enable {
      services.postgresql = {
        enable = true;
        package = pkgs.postgresql_17;
        extensions = with config.services.postgresql.package.pkgs; [ pgvector ];
        ensureDatabases = [ db.name ];
        ensureUsers = [{
          name = db.user;
          # ensureDBOwnership requires the database name to match the user name.
          # db.name ("ironclaw") ≠ db.user ("alex"), so ownership is granted
          # via ALTER DATABASE in ironclaw-db-setup below instead.
        }];
      };

      # Oneshot service: set DB owner, enable pgvector extension. Runs on
      # every boot but is a no-op once both are already in place.
      systemd.services.ironclaw-db-setup = {
        description = "Enable pgvector extension for ironclaw database";
        after = [ "postgresql.service" "postgresql-setup.service" ];
        requires = [ "postgresql.service" "postgresql-setup.service" ];
        before = lib.optional cfg.runDaemon "ironclaw.service";
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          User = "postgres";
          ExecStart = pkgs.writeShellScript "ironclaw-db-setup" ''
            ${config.services.postgresql.package}/bin/psql postgres \
              -c "ALTER DATABASE ${db.name} OWNER TO ${db.user};"
            ${config.services.postgresql.package}/bin/psql -d ${db.name} \
              -c "CREATE EXTENSION IF NOT EXISTS vector;"
          '';
        };
      };
    })

    # ── systemd daemon (opt-in, after onboard is complete) ──────────────
    (lib.mkIf cfg.runDaemon {
      systemd.services.ironclaw = {
        description = "ironclaw agent OS";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ]
          ++ lib.optional db.enable "postgresql.service"
          ++ lib.optional db.enable "ironclaw-db-setup.service";
        requires = lib.optional db.enable "ironclaw-db-setup.service";
        environment = lib.optionalAttrs db.enable {
          DATABASE_URL = "postgresql:///${db.name}?host=/run/postgresql&user=${db.user}";
        };
        serviceConfig = {
          ExecStart = "${pkgs.ironclaw}/bin/ironclaw run";
          Restart = "on-failure";
          User = db.user;
        };
      };
    })

    # ── signal-cli systemd daemon ───────────────────────────────────────
    (lib.mkIf sc.enable {
      systemd.services.signal-cli-http = {
        description = "signal-cli HTTP daemon for ironclaw Signal channel";
        wantedBy = [ "multi-user.target" ];
        after = [ "network.target" ];
        serviceConfig = {
          ExecStart = "${pkgs.signal-cli}/bin/signal-cli daemon --http=127.0.0.1:${toString sc.httpPort}";
          Restart = "always";
          User = "alex";
        };
      };
    })
  ]);
}
