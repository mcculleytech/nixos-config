{ lib, pkgs, config, ... }:
let
  cfg = config.vault-indexer;
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
