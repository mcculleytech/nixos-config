{ lib, pkgs, config, ... }:
let
  cfg = config.vault-indexer;
  # Derive the /health URL from the MCP URL. Health is unauthenticated
  # (the agent-memory-mcp middleware exempts it) so a plain curl with no
  # bearer can probe readiness without bringing the indexer's token into
  # the wait script.
  healthUrl = (lib.removeSuffix "/mcp" cfg.agentMemoryUrl) + "/health";
in
{
  options.vault-indexer = {
    enable = lib.mkEnableOption "periodic vault → agent_memory indexer";

    vaultRoot = lib.mkOption {
      type = lib.types.path;
      default = "/home/alex/obsidian/Barrow-Downs";
      description = "Path to the Obsidian vault to index.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "alex";
      description = ''
        UNIX user that runs the indexer. Must be able to read the vault
        directory. Default `alex` matches the vault owner; the user also
        needs to read the bearer-token secret file (we own-it to `alex`
        in the sops declaration).
      '';
    };

    agentMemoryUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.lab.hosts.saruman.tailnetIp}:4280/mcp";
      description = "Streamable-HTTP URL for the agent-memory MCP server.";
    };

    onCalendar = lib.mkOption {
      type = lib.types.str;
      default = "hourly";
      description = "systemd OnCalendar spec for the indexer timer.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Bearer token used by the indexer to call agent-memory-mcp. Owned by
    # the indexer's runtime user so it can read the value.
    sops.secrets.vault_indexer_agent_memory_token = {
      owner = cfg.user;
      group = "users";
      mode = "0400";
    };

    # `vault-indexer --version` on PATH for operator convenience.
    environment.systemPackages = [ pkgs.vault-indexer ];

    systemd.services.vault-indexer = {
      description = "Index vault chunks into agent_memory";
      after = [
        "network-online.target"
        "tailscaled.service"
        "agent-memory-mcp.service"
      ];
      wants = [ "network-online.target" "tailscaled.service" ];

      environment = {
        VAULT_INDEXER_VAULT = builtins.toString cfg.vaultRoot;
        VAULT_INDEXER_AGENT_MEMORY_URL = cfg.agentMemoryUrl;
        VAULT_INDEXER_TOKEN_FILE = config.sops.secrets.vault_indexer_agent_memory_token.path;
      };

      serviceConfig = {
        Type = "oneshot";
        # Wait for agent-memory-mcp to be HTTP-ready before firing the
        # indexer. systemd's `After=` only orders unit START, not
        # readiness. With version stamping in place every deploy restarts
        # agent-memory-mcp; if the vault-indexer timer fires during that
        # ~2-3s startup window (very likely with Persistent=true catching
        # up missed runs), it races the restart and dies with ConnectError.
        # Poll /health (no bearer required) until the MCP responds 200 OK.
        ExecStartPre = [
          (pkgs.writeShellScript "wait-for-agent-memory-mcp" ''
            set -eu
            for i in $(seq 1 30); do
              if ${pkgs.curl}/bin/curl -fsS -m 2 "${healthUrl}" > /dev/null 2>&1; then
                exit 0
              fi
              sleep 1
            done
            echo "agent-memory-mcp /health did not come up in 30s at ${healthUrl}" >&2
            exit 1
          '')
        ];
        ExecStart = "${pkgs.vault-indexer}/bin/vault-indexer";
        User = cfg.user;
        Group = "users";
        # Modest hardening; the indexer only needs to read the vault and
        # speak HTTP outbound.
        ProtectSystem = "strict";
        ProtectHome = false;  # vault is under /home
        PrivateTmp = true;
        NoNewPrivileges = true;
      };
    };

    systemd.timers.vault-indexer = {
      description = "Run vault-indexer on a schedule";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = cfg.onCalendar;
        Persistent = true;          # fire missed runs at boot — handles initial bootstrap
        RandomizedDelaySec = "5min"; # jitter so we don't slam Ollama at exactly :00
        Unit = "vault-indexer.service";
      };
    };
  };
}
