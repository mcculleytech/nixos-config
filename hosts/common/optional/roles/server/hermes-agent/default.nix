{ lib, config, ... }:
let
  cfg = config.hermes-agent;
  # Tailnet IP of the host running both Hermes and the MCP servers. The MCPs
  # bind tailnet-only (resolved at service start via `tailscale ip -4`), so
  # even from saruman itself the path is tailnet0, not loopback. Pulled from
  # hosts-data.nix so we have one place to update if the IP ever changes.
  mcpHost = config.lab.hosts.saruman.tailnetIp;
in
{
  # ─── Module structure ────────────────────────────────────────────────────
  # This module is split into four files for navigability:
  #   • default.nix  — option declarations + top-level wiring (this file)
  #   • secrets.nix  — sops.secrets + sops.templates."hermes-agent.env"
  #   • state.nix    — systemd.tmpfiles + activation chown migration
  #   • service.nix  — services.hermes-agent + systemd unit overrides
  #                    (also owns the inline localesPatch derivation)
  # The split is purely organisational; each sub-file is a normal NixOS
  # submodule guarded by `lib.mkIf cfg.enable`. Sibling assets:
  #   • SOUL.md           — persona prompt (read by service.nix)
  #   • sitecustomize.py  — i18n + /model-alias patches (read by service.nix)
  imports = [
    ./secrets.nix
    ./state.nix
    ./service.nix
  ];

  options.hermes-agent = {
    enable = lib.mkEnableOption "Hermes (NousResearch/hermes-agent) Signal bot wired to our MCP services";

    # ─── Single-model setup with /model overrides ──────────────────────────
    # Gemini 2.5 Flash on OpenRouter is the default for every Signal turn.
    # Alex switches models per-conversation by sending slash commands in
    # Signal: `/model <alias>` (see model_aliases in service.nix for the
    # curated short names — opus, local, flash, etc.). Sessions reset after
    # `sessionIdleMinutes` of inactivity, snapping back to default.
    #
    # Why not orchestrator + delegate? We tried it (Gemma 8B and Flash
    # Lite tier-1, V4 Pro tier-2). hermes-agent enforces subagent
    # toolset ⊆ parent toolset for security, so you can't give the
    # subagent more MCPs than the cheap orchestrator. Without that
    # asymmetry, cheap orchestrators use tools themselves instead of
    # delegating, defeating the entire pattern.

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "google/gemini-2.5-flash";
      description = ''
        The model that handles every Signal turn unless alex has
        sent `/model <slug>` to override for the session. Gemini 2.5
        Flash via OpenRouter's BYOK routing — billed against alex's
        Google AI Studio account where the $10/mo Pro-subscription
        credit covers normal use-it-or-lose-it. ZDR comes from his
        Google paid tier; the provider pin below restricts OR to the
        google-ai-studio route so BYOK actually fires.

        Was deepseek/deepseek-v4-pro pre-2026-05-14 — V4 Pro remains
        available via `/model deep` for tool-heavy or harder
        reasoning turns where Flash falls short.
      '';
    };

    localModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3:4b-instruct-28k";
      description = ''
        Ollama tag for the local model accessible via the `/model local`
        alias, served on saruman's GTX 1080 Ti. Qwen3 4B Instruct
        (28K ctx, tool-use, non-thinking) — fits comfortably in VRAM and
        is well-suited to fast tool-calling agent turns. Replaced the
        retired gemma4-8b-16k wrapper 2026-06-16.
      '';
    };

    localBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://127.0.0.1:11434/v1";
      description = "Base URL of the local Ollama OpenAI-compatible endpoint.";
    };

    localApiKey = lib.mkOption {
      type = lib.types.str;
      default = "ollama";
      description = "API key for local Ollama (Ollama doesn't validate; sentinel).";
    };

    # ── Mac (faramir) LM Studio — `/model maccoder` ──
    macCoderModel = lib.mkOption {
      type = lib.types.str;
      default = "qwen3-coder-30b-a3b-instruct-mlx";
      description = ''
        LM Studio model identifier served on faramir (the Mac) via the
        `/model maccoder` alias. Qwen3-Coder-30B-A3B-Instruct (MLX 4-bit) —
        a coding/agentic model far beyond what the 1080 Ti can host.
        Requires LM Studio on faramir to be serving on the local network
        (not loopback-only) and the Mac to be awake.
      '';
    };

    macCoderBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.lab.hosts.faramir.tailnetIp}:1234/v1";
      description = "Base URL of faramir's LM Studio OpenAI-compatible endpoint over the tailnet.";
    };

    macCoderApiKey = lib.mkOption {
      type = lib.types.str;
      default = "lm-studio";
      description = "API key for faramir's LM Studio (not validated; sentinel).";
    };

    sessionIdleMinutes = lib.mkOption {
      type = lib.types.int;
      default = 120;
      description = ''
        Minutes of Signal inactivity before the session resets and any
        `/model` override snaps back to the default model. 120 (2 h) is
        long enough to span a normal back-and-forth conversation but
        short enough that ad-hoc overrides don't linger overnight.
        Daily 4am reset (hermes-agent built-in) still fires too.
      '';
    };

    delegateProviders = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ "parasail" "atlas-cloud" "deepinfra" "novita" "venice" ];
      description = ''
        OpenRouter provider slugs allowed to serve DeepSeek traffic.
        All must be US-HQ'd and honor zero-retention. Together is
        omitted despite being US-HQ'd because its DeepSeek-V4-Pro
        endpoint has been flapping (~65%% uptime when last checked).
      '';
    };

    agentMemoryUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4280/mcp";
      description = "Streamable-HTTP URL for the agent-memory MCP server.";
    };

    vaultUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4281/mcp";
      description = "Streamable-HTTP URL for the vault MCP server.";
    };

    signalMcpUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4282/mcp";
      description = "Streamable-HTTP URL for the outbound Signal MCP (gated send).";
    };

    radicaleMcpUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4283/mcp";
      description = "Streamable-HTTP URL for the Radicale CalDAV/CardDAV MCP.";
    };

    minifluxMcpUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4284/mcp";
      description = "Streamable-HTTP URL for the Miniflux RSS MCP.";
    };

    escalatorMcpUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4285/mcp";
      description = "Streamable-HTTP URL for the escalator MCP (consult_expert tool).";
    };

    gcalMcpUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4286/mcp";
      description = "Streamable-HTTP URL for the Google Calendar MCP.";
    };

    prometheusMcpUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4287/mcp";
      description = "Streamable-HTTP URL for the Prometheus + Alertmanager MCP.";
    };

    emailMcpUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${mcpHost}:4288/mcp";
      description = "Streamable-HTTP URL for the email MCP (Proton Bridge IMAP/SMTP, gated send).";
    };
  };

  config = lib.mkIf cfg.enable {
    # Hermes is meaningless without the signal-cli HTTP daemon — turn it on.
    signal-cli.enable = true;

    # ─── Run hermes-agent as alex, not a dedicated system user ──────────────
    # Why: bundled skills (google-workspace, github-*, claude-code) all
    # assume the operator's auth state is at well-known paths under the
    # service user's HOME (~/.claude/, gh's keychain, etc.). With a
    # dedicated `hermes` system user, every such skill needs a workaround
    # (sops-managed credential copies, sudoers rule to invoke claude as
    # alex, etc.). Running the service as alex eliminates the entire class
    # of workarounds — claude finds alex's auth, gh finds alex's keyring,
    # google-workspace can write its tokens straight into alex's profile.
    #
    # Trade-off: the service loses process-isolation from alex's
    # interactive session. Acceptable for a single-user homelab on
    # tailnet (no untrusted human accounts on this host).
    #
    # createUser = false stops the upstream module from declaring the
    # hermes user (alex is declared elsewhere in our config); we still
    # need to ensure the `hermes` GROUP exists because we keep using it
    # to share secrets with sibling MCP service users (gcal-mcp,
    # escalator-mcp).

    # The `hermes` group survives the user removal — it stays as a
    # shared-secret group: alex + escalator_mcp + gcal_mcp users are
    # all members, secrets are mode 0440 group=hermes.
    users.groups.hermes = { };
    # Add alex to the hermes group so the service (running as alex) can
    # read its own sops-rendered EnvironmentFile (mode 0400 owner=alex)
    # AND the shared mode-0440 group=hermes secrets the MCPs depend on.
    users.users.alex.extraGroups = [ "hermes" ];
  };
}
