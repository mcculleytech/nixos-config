{ lib, pkgs, config, ... }:
let
  cfg = config.agent-memory;
  dbName = "agent_memory";
  dbUser = "agent_memory_mcp"; # OS user == Postgres role for peer auth via unix socket
in
{
  options.agent-memory = {
    enable = lib.mkEnableOption "shared agent memory (PostgreSQL 17 + pgvector + MCP gateway)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4280;
      description = "TCP port the MCP gateway listens on. Bound to the tailnet IP only.";
    };

    bindIp = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = ''
        IPv4 address the MCP gateway binds to. "auto" resolves the host's tailnet
        IP via `tailscale ip -4` at service start. Set explicitly only for
        testing on a non-tailnet box.
      '';
    };

    tailnetInterface = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = "Interface on which to open the MCP port in the firewall.";
    };
  };

  config = lib.mkIf cfg.enable {
    # ─── system user (peer-auth: OS user == Postgres role) ─────────────────
    users.users.${dbUser} = {
      isSystemUser = true;
      group = dbUser;
      home = "/var/lib/agent-memory-mcp";
      createHome = true;
      description = "agent-memory-mcp service user";
    };
    users.groups.${dbUser} = {};

    # ─── PostgreSQL + pgvector ─────────────────────────────────────────────
    # Do NOT pin services.postgresql.package here. Other services on the host
    # (immich, paperless) already pin postgres via lib.mkDefault to whatever
    # version their data was initialized with. Overriding that version triggers
    # an initdb on a new version-suffixed data dir (/var/lib/postgresql/<N>),
    # leaving the original data orphaned. Match whatever the host has.
    services.postgresql = {
      enable = true;
      extensions = with config.services.postgresql.package.pkgs; [ pgvector ];
      ensureDatabases = [ dbName ];
      ensureUsers = [{
        name = dbUser;
        # ensureDBOwnership requires DB name == user name; ours differ
        # (agent_memory vs agent_memory_mcp), so ownership is granted in
        # agent-memory-db-setup below instead.
      }];
    };

    # ─── DB provisioning oneshot ───────────────────────────────────────────
    # Idempotent: sets owner, enables pgvector, applies schema. No-op once
    # everything is in place.
    systemd.services.agent-memory-db-setup = {
      description = "Provision agent_memory schema + pgvector extension";
      after = [ "postgresql.service" "postgresql-setup.service" ];
      requires = [ "postgresql.service" "postgresql-setup.service" ];
      before = [ "agent-memory-mcp.service" ];
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        User = "postgres";
      };
      script = ''
        set -eu
        psql=${config.services.postgresql.package}/bin/psql
        "$psql" postgres -c "ALTER DATABASE ${dbName} OWNER TO ${dbUser};"
        "$psql" -d ${dbName} -c "CREATE EXTENSION IF NOT EXISTS vector;"
        "$psql" -d ${dbName} -f ${./schema.sql}
        # Tables created by `postgres` in schema.sql; transfer ownership so the
        # application role (peer-auth) can read/write/alter them. Idempotent.
        "$psql" -d ${dbName} -c "ALTER TABLE projects OWNER TO ${dbUser};"
        "$psql" -d ${dbName} -c "ALTER TABLE memories OWNER TO ${dbUser};"
      '';
    };

    # ─── sops secret: client→token JSON map ────────────────────────────────
    sops.secrets.agent_memory_mcp_tokens = {
      owner = dbUser;
      group = dbUser;
      mode = "0400";
      # Restart the MCP when the token map changes so the new client takes
      # effect without a manual systemctl restart after every deploy.
      restartUnits = [ "agent-memory-mcp.service" ];
    };

    # ─── state dir persistence ─────────────────────────────────────────────
    environment.persistence."/persist".directories = [
      { directory = "/var/lib/agent-memory-mcp"; user = dbUser; group = dbUser; mode = "0750"; }
    ];

    systemd.tmpfiles.rules = [
      "d /var/lib/agent-memory-mcp 0750 ${dbUser} ${dbUser} -"
      # Backup landing zone — postgres-only so pg_dump output isn't world-readable.
      "d /persist/backups 0755 root root -"
      "d /persist/backups/postgres 0700 postgres postgres -"
      "d /persist/backups/postgres/agent_memory 0700 postgres postgres -"
    ];

    # ─── MCP gateway systemd unit ──────────────────────────────────────────
    systemd.services.agent-memory-mcp = {
      description = "Agent memory MCP gateway (pgvector + Ollama)";
      after = [
        "network.target"
        "postgresql.service"
        "agent-memory-db-setup.service"
        "tailscaled.service"
      ];
      requires = [ "agent-memory-db-setup.service" ];
      wants = [ "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      # Tailscale CLI on PATH so the server can resolve its own tailnet IP.
      path = [ config.services.tailscale.package ];

      environment = {
        AGENT_MEMORY_BIND_IP = cfg.bindIp;
        AGENT_MEMORY_PORT = toString cfg.port;
        AGENT_MEMORY_DB_DSN = "postgresql:///${dbName}?host=/run/postgresql&user=${dbUser}";
        AGENT_MEMORY_TOKENS_FILE = config.sops.secrets.agent_memory_mcp_tokens.path;
        OLLAMA_URL = "http://127.0.0.1:11434";
        OLLAMA_EMBED_MODEL = "nomic-embed-text";
      };

      serviceConfig = {
        ExecStart = "${pkgs.agent-memory-mcp}/bin/agent-memory-mcp";
        User = dbUser;
        Group = dbUser;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/agent-memory-mcp" ];
      };
    };

    # Open the gateway port on the tailnet interface only — never on LAN/WAN.
    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];

    # ─── Daily pg_dump of agent_memory ─────────────────────────────────────
    # Custom format (-Fc): smaller than plain SQL, restorable in parallel via
    # pg_restore --jobs, and pg_dump compresses inline. 30-day retention is
    # enforced inline; off-host replication (NAS / faramir) is deliberately
    # not wired here — single-host snapshots cover DB corruption and
    # accidental deletes, not full saruman loss. Separate decision.
    systemd.services.agent-memory-backup = {
      description = "Daily pg_dump of agent_memory database";
      after = [ "postgresql.service" "agent-memory-db-setup.service" ];
      requires = [ "postgresql.service" ];
      serviceConfig = {
        Type = "oneshot";
        User = "postgres";
        Group = "postgres";
        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/persist/backups/postgres/agent_memory" ];
      };
      script = ''
        set -eu
        ts=$(${pkgs.coreutils}/bin/date -u +%Y-%m-%d)
        out=/persist/backups/postgres/agent_memory/agent_memory-$ts.dump
        ${config.services.postgresql.package}/bin/pg_dump \
          --format=custom \
          --file="$out.tmp" \
          ${dbName}
        ${pkgs.coreutils}/bin/mv "$out.tmp" "$out"
        ${pkgs.findutils}/bin/find /persist/backups/postgres/agent_memory \
          -name 'agent_memory-*.dump' -mtime +30 -delete
      '';
    };

    systemd.timers.agent-memory-backup = {
      description = "Daily timer for agent-memory pg_dump";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "*-*-* 03:00:00";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
