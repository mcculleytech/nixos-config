{ lib, pkgs, config, ... }:
let
  cfg = config.hermes-agent;
  signalCfg = config.signal-cli;
in
{
  options.hermes-agent = {
    enable = lib.mkEnableOption "Hermes (NousResearch/hermes-agent) Signal bot wired to our MCP services";

    model = lib.mkOption {
      type = lib.types.str;
      default = "anthropic/claude-opus-4.6";
      description = ''
        Model identifier for the agent's LLM. Default uses native Anthropic
        provider; switch to e.g. "openrouter/nousresearch/hermes-3-llama-3.1-405b"
        and add an OPENROUTER_API_KEY env var in the sops template to migrate.
      '';
    };

    agentMemoryUrl = lib.mkOption {
      type = lib.types.str;
      # NOTE: saruman's tailnet IP — agent-memory-mcp/vault-mcp bind only to
      # the tailnet interface (resolved at service start via `tailscale ip -4`),
      # not the LAN IP. From saruman itself, the tailnet IP routes back through
      # tailscale0. Hardcoded here because we don't track tailnet IPs in
      # hosts-data.nix yet; if you move Hermes off saruman, override this.
      default = "http://100.104.242.112:4280/mcp";
      description = "Streamable-HTTP URL for the agent-memory MCP server.";
    };

    vaultUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://100.104.242.112:4281/mcp";
      description = "Streamable-HTTP URL for the vault MCP server.";
    };
  };

  config = lib.mkIf cfg.enable {
    # Hermes is meaningless without the signal-cli HTTP daemon — turn it on.
    signal-cli.enable = true;

    # ─── sops scalars (values added via `sops secrets/main.yaml`) ───────────
    sops.secrets = {
      anthropic_api_key = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      hermes_bot_account = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      hermes_allowlist = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_agent_memory = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_vault = { owner = "hermes"; group = "hermes"; mode = "0400"; };
    };

    # ─── EnvironmentFile rendered from sops at boot ────────────────────────
    # Hermes reads every secret it needs from this single file. No plaintext
    # ever lives in the Nix store.
    sops.templates."hermes-agent.env" = {
      owner = "hermes";
      group = "hermes";
      mode = "0400";
      content = ''
        ANTHROPIC_API_KEY=${config.sops.placeholder.anthropic_api_key}
        SIGNAL_ACCOUNT=${config.sops.placeholder.hermes_bot_account}
        SIGNAL_ALLOWED_USERS=${config.sops.placeholder.hermes_allowlist}
        HERMES_AGENT_MEMORY_TOKEN=${config.sops.placeholder.future_hermes_agent_memory}
        HERMES_VAULT_TOKEN=${config.sops.placeholder.future_hermes_vault}
      '';
    };

    # ─── Upstream module configuration ─────────────────────────────────────
    services.hermes-agent = {
      enable = true;

      environmentFiles = [ config.sops.templates."hermes-agent.env".path ];

      environment = {
        SIGNAL_HTTP_URL = "http://127.0.0.1:${toString signalCfg.httpPort}";
        HERMES_HOME = "/var/lib/hermes/.hermes";
      };

      settings = {
        model = {
          provider = "anthropic";
          default = cfg.model;
          # api_key picked up from ANTHROPIC_API_KEY env var
        };
      };

      mcpServers = {
        agent-memory = {
          url = cfg.agentMemoryUrl;
          headers.Authorization = "Bearer \${HERMES_AGENT_MEMORY_TOKEN}";
        };
        vault = {
          url = cfg.vaultUrl;
          headers.Authorization = "Bearer \${HERMES_VAULT_TOKEN}";
        };
      };
    };

    # Guard: the hermes-agent service should not start until signal-cli has
    # been linked. The upstream unit will retry on its own, but adding the
    # explicit ordering keeps the journal cleaner. Also widen the stop
    # timeout — upstream emits a runtime warning if TimeoutStopSec < 210s
    # because the agent's in-flight drain can take up to 180s; the NixOS
    # module ships 90s by default which trips that warning every boot.
    systemd.services.hermes-agent = {
      after = [ "signal-cli.service" ];
      wants = [ "signal-cli.service" ];
      serviceConfig.TimeoutStopSec = 240;
    };
  };
}
