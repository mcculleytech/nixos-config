{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.hermes-agent;
  signalCfg = config.signal-cli;
  # Tailnet IP of the host running both Hermes and the MCP servers. The MCPs
  # bind tailnet-only (resolved at service start via `tailscale ip -4`), so
  # even from saruman itself the path is tailnet0, not loopback. Pulled from
  # hosts-data.nix so we have one place to update if the IP ever changes.
  mcpHost = config.lab.hosts.saruman.tailnetIp;

  # ─── Morning-briefing cron job definition ────────────────────────────────
  # The job SCAFFOLDING (id, schedule, model) lives in Nix — declarative
  # and git-tracked. The PROMPT content lives in sops (secrets/cron-jobs.yaml,
  # key `morning_briefing_prompt`) because it includes alex's E.164 phone
  # number (recipient for signal_send_message). sops.templates below
  # renders the final jobs.json with the prompt substituted, then an
  # activation script copies that to /var/lib/hermes/.hermes/cron/jobs.json.
  #
  # Adding more private cron jobs: add another key in secrets/cron-jobs.yaml,
  # add a corresponding sops.secrets + sops.templates substitution here,
  # extend the jobs[] list in the template content below.

  # ─── i18n locales patch ───────────────────────────────────────────────────
  # Upstream's pyproject.toml + nix derivation don't ship `locales/` to the
  # installed wheel, so agent/i18n.py's `Path(__file__).parent.parent/locales`
  # path resolves to nothing and slash-command responses come back as raw
  # i18n keys (`gateway.model.switched`, etc.). We can't patch the venv
  # (uv2nix-built, deep in /nix/store), but we CAN inject a sitecustomize.py
  # via PYTHONPATH that monkey-patches `agent.i18n._locales_dir` at Python
  # startup — *before* any catalog lookup happens. Belt-and-suspenders the
  # env-var path so any code that respects it works too.
  localesPatch = pkgs.runCommand "hermes-locales-patch" {} ''
    mkdir -p $out/locales $out/python
    cp -r ${inputs.hermes-agent}/locales/* $out/locales/
    cat > $out/python/sitecustomize.py <<'PYEOF'
"""Inject locales/ into agent.i18n at Python startup.

Hermes-agent's upstream wheel omits the locales/ YAML files, so the
agent's i18n module returns raw keys for every translatable string.
This sitecustomize.py runs during site initialization (before any
user code, before hermes-agent's own modules import), imports the
i18n module, and monkey-patches its `_locales_dir` function to point
at our copy of the YAML catalogs.
"""
import os
from pathlib import Path

_override = Path(os.environ.get("HERMES_LOCALES_DIR", ""))
if _override.is_dir():
    try:
        import agent.i18n as _i18n_mod  # noqa: E402
        _i18n_mod._locales_dir = lambda: _override
        # Also invalidate any cached catalog if i18n already lazily-loaded one.
        for _cache_attr in ("_CATALOGS", "_catalogs", "_CACHE"):
            if hasattr(_i18n_mod, _cache_attr):
                getattr(_i18n_mod, _cache_attr).clear()
    except ImportError:
        # hermes-agent isn't on the path — quietly do nothing.
        pass
PYEOF
  '';
in
{
  options.hermes-agent = {
    enable = lib.mkEnableOption "Hermes (NousResearch/hermes-agent) Signal bot wired to our MCP services";

    # ─── Single-model setup with /model overrides ──────────────────────────
    # DeepSeek V4 Pro on OpenRouter is the default for every Signal turn.
    # Alex switches models per-conversation by sending slash commands in
    # Signal: `/model <alias>` (see model_aliases in settings below for
    # the curated short names — opus, local, flash, etc.). Sessions reset
    # after `sessionIdleMinutes` of inactivity, snapping back to default.
    #
    # Why not orchestrator + delegate? We tried it (Gemma 8B and Flash
    # Lite tier-1, V4 Pro tier-2). hermes-agent enforces subagent
    # toolset ⊆ parent toolset for security, so you can't give the
    # subagent more MCPs than the cheap orchestrator. Without that
    # asymmetry, cheap orchestrators use tools themselves instead of
    # delegating, defeating the entire pattern.

    defaultModel = lib.mkOption {
      type = lib.types.str;
      default = "deepseek/deepseek-v4-pro";
      description = ''
        The model that handles every Signal turn unless alex has
        sent `/model <slug>` to override for the session. DeepSeek
        V4 Pro via OpenRouter — strong tool use, ~$0.435 in / $0.87
        out per Mtok, pinned to ZDR US-HQ providers via
        `extra_body.provider` below.
      '';
    };

    localModel = lib.mkOption {
      type = lib.types.str;
      default = "gemma4-8b-16k";
      description = ''
        Ollama tag for the local Gemma model accessible via the
        `/model local` alias. Modelfile-wrapped from gemma4:latest
        with num_ctx=16384 baked in (32K spilled to CPU and tanked
        latency).
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

    # ── MacBook (faramir) — LM Studio hosting Gemma 4 26B A4B over tailnet ──
    macModel = lib.mkOption {
      type = lib.types.str;
      default = "mlx-community/gemma-4-26b-a4b-it";
      description = ''
        LM Studio model identifier for the MacBook-hosted Gemma 4 26B
        A4B IT (MLX-quantized). Reachable via `/model mac` in Signal.
      '';
    };

    macBaseUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://100.90.82.127:1234/v1";
      description = ''
        Faramir's tailnet IP at LM Studio's default OpenAI-compatible
        port (1234). Hardcoded since faramir isn't NixOS-managed and
        doesn't appear in `hosts-data.nix`.
      '';
    };

    macApiKey = lib.mkOption {
      type = lib.types.str;
      default = "lmstudio";
      description = ''
        API key for LM Studio. Empirically, hermes-agent's
        `model_aliases.*.api_key` field does NOT expand ${"\${VARS}"}
        substitutions (only mcpServers.headers does). So putting a sops
        reference here ended up sending the literal "${"\${LMSTUDIO_API_KEY}"}"
        string as the bearer token. Easier path: disable LM Studio's
        "Require API key" toggle and rely on tailnet-only access as
        the security perimeter. Then this sentinel just satisfies
        hermes' shape requirement.
      '';
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

    morningBriefingEnable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Whether to register the 6 AM morning-briefing cron job.
        Job creates today's daily note in the vault, pulls radicale
        + Google calendar events, summarizes, and sends via Signal.
        Pinned to `google/gemini-2.5-flash-lite` via BYOK for ~free
        execution against the Google quota.
      '';
    };

    morningBriefingSchedule = lib.mkOption {
      type = lib.types.str;
      default = "0 6 * * *";
      description = "Cron expression for the morning briefing (default 6:00 AM daily).";
    };

    morningBriefingModel = lib.mkOption {
      type = lib.types.str;
      default = "deepseek/deepseek-v4-pro";
      description = ''
        Model that runs the briefing. DeepSeek V4 Pro — proven
        reliable tool calls via OR, ~$0.02/run = ~$0.60/mo. Tried
        Gemini Flash Lite first (would have been near-free via BYOK)
        but it wrote Python via execute_code instead of calling MCP
        tools directly. V4 Pro doesn't have that confusion.
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
  };

  config = lib.mkIf cfg.enable {
    # Hermes is meaningless without the signal-cli HTTP daemon — turn it on.
    signal-cli.enable = true;

    # ─── sops scalars (values added via `sops secrets/main.yaml`) ───────────
    sops.secrets = {
      # The single key that fronts ALL model traffic. A runtime sub-key
      # created via scripts/openrouter-bootstrap.sh with a one-shot
      # provisioning key (which is never stored). Sub-key carries a hard
      # monthly credit cap. The user's Gemini key is registered in OR
      # as BYOK so tier-1 inference still bills against the Google quota.
      # Shared with escalator-mcp (which also needs to make OR calls).
      # mode 0440 so anyone in the hermes group can read; escalator-mcp's
      # service user joins the hermes group via its module.
      openrouter_api_key = { owner = "hermes"; group = "hermes"; mode = "0440"; };
      # Tavily for web_search / web_extract tools. Free tier = 1000
      # searches/mo at https://app.tavily.com — plenty for personal use.
      tavily_api_key = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      # Morning briefing prompt content (contains alex's E.164 as the
      # Signal recipient). Lives in secrets/hermes-cron-jobs.yaml — a
      # dedicated sops file for private hermes scheduled-task content.
      # restartUnits bounces hermes-agent when the prompt is edited so
      # the new content gets picked up immediately, no manual restart.
      morning_briefing_prompt = {
        owner = "hermes";
        group = "hermes";
        mode = "0400";
        sopsFile = ../../../../../../secrets/hermes-cron-jobs.yaml;
        restartUnits = [ "hermes-agent.service" ];
      };
      hermes_bot_account = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      hermes_allowlist = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_agent_memory = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_vault = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_signal = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_radicale = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_miniflux = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_gcal = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      future_hermes_escalator = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      hermes_github_pat = { owner = "hermes"; group = "hermes"; mode = "0400"; };
      # Rendered directly into HERMES_HOME at the path the google-workspace
      # skill's setup.py expects (hard-coded `${HERMES_HOME}/google_client_secret.json`).
      # Mode 0440 (group-readable) so gcal-mcp's service user, which has
      # secondary membership in the `hermes` group, can read it for
      # token refresh.
      hermes_google_client_secret = {
        owner = "hermes";
        group = "hermes";
        mode = "0440";
        path = "/var/lib/hermes/.hermes/google_client_secret.json";
      };
    };

    # The skill expects $HERMES_HOME to exist before sops writes the
    # client_secret file into it. The hermes-agent service would create it
    # on first run, but activation-time sops symlinks land earlier.
    systemd.tmpfiles.rules = [
      # HERMES_HOME has to allow group traversal (0750 not 0700) so
      # gcal-mcp's service user (member of the `hermes` group via
      # extraGroups) can reach the google credential + token files.
      "d /var/lib/hermes/.hermes 0750 hermes hermes -"
      "d /var/lib/hermes/.hermes/cron 2770 hermes hermes -"
      # The skill writes google_token.json with the running user's
      # default umask (typically 0600). Force group-readable so gcal-mcp
      # can read it for token refreshes. tmpfiles's `z` mode adjusts an
      # EXISTING file without creating it.
      "z /var/lib/hermes/.hermes/google_token.json 0640 hermes hermes -"
    ];

    # Build jobs.json at activation time by combining the Nix-defined
    # job scaffolding (id, schedule, model) with the sops-rendered
    # prompt text. We can't just stuff a sops placeholder into a JSON
    # string via sops.templates — sops substitutes verbatim and
    # multi-line prompt content breaks the JSON. So instead we use jq
    # to splice the raw prompt (which sops decrypts into a plain text
    # file) into a proper JSON document, with jq handling the
    # string-escaping for us.
    system.activationScripts.hermes-cron-seed = lib.mkIf cfg.morningBriefingEnable {
      text = ''
        prompt_file="${config.sops.secrets.morning_briefing_prompt.path}"
        if [ ! -r "$prompt_file" ]; then
          echo "hermes-cron-seed: WARN prompt file not readable; skipping" >&2
          exit 0
        fi
        ${pkgs.jq}/bin/jq -n \
          --rawfile prompt "$prompt_file" \
          --arg schedule "${cfg.morningBriefingSchedule}" \
          --arg model "${cfg.morningBriefingModel}" \
          '{
            jobs: [{
              id: "mornbrf000001",
              name: "morning-briefing",
              schedule: { kind: "cron", display: "every day at 6:00 AM", expr: $schedule },
              deliver: "local",
              prompt: $prompt,
              model: $model,
              provider: "openrouter",
              enabled: true,
              state: "scheduled",
              created_at: "2026-05-13T00:00:00Z"
            }],
            updated_at: "2026-05-13T00:00:00Z"
          }' > /var/lib/hermes/.hermes/cron/jobs.json.tmp
        install -o hermes -g hermes -m 0640 \
          /var/lib/hermes/.hermes/cron/jobs.json.tmp \
          /var/lib/hermes/.hermes/cron/jobs.json
        rm -f /var/lib/hermes/.hermes/cron/jobs.json.tmp
      '';
      deps = [ "setupSecrets" "users" "groups" ];
    };

    # ─── EnvironmentFile rendered from sops at boot ────────────────────────
    # Hermes reads every secret it needs from this single file. No plaintext
    # ever lives in the Nix store.
    sops.templates."hermes-agent.env" = {
      owner = "hermes";
      group = "hermes";
      mode = "0400";
      # Hermes reads every secret via this template fan-out. When any of
      # the underlying sops placeholders change, the template re-renders
      # and we want the agent to pick up the new values. The per-secret
      # entries above feed only this template, so restartUnits on the
      # template covers them all without per-secret duplication.
      restartUnits = [ "hermes-agent.service" ];
      content = ''
        OPENROUTER_API_KEY=${config.sops.placeholder.openrouter_api_key}
        TAVILY_API_KEY=${config.sops.placeholder.tavily_api_key}
        SIGNAL_ACCOUNT=${config.sops.placeholder.hermes_bot_account}
        SIGNAL_ALLOWED_USERS=${config.sops.placeholder.hermes_allowlist}
        HERMES_AGENT_MEMORY_TOKEN=${config.sops.placeholder.future_hermes_agent_memory}
        HERMES_VAULT_TOKEN=${config.sops.placeholder.future_hermes_vault}
        HERMES_SIGNAL_MCP_TOKEN=${config.sops.placeholder.future_hermes_signal}
        HERMES_RADICALE_MCP_TOKEN=${config.sops.placeholder.future_hermes_radicale}
        HERMES_MINIFLUX_MCP_TOKEN=${config.sops.placeholder.future_hermes_miniflux}
        HERMES_GCAL_MCP_TOKEN=${config.sops.placeholder.future_hermes_gcal}
        HERMES_ESCALATOR_MCP_TOKEN=${config.sops.placeholder.future_hermes_escalator}
        GH_TOKEN=${config.sops.placeholder.hermes_github_pat}
      '';
    };

    # ─── Upstream module configuration ─────────────────────────────────────
    services.hermes-agent = {
      enable = true;

      # Note: there's a known cosmetic bug where slash-command responses
      # come back as raw i18n keys (`gateway.model.switched` etc.) because
      # upstream forgets to bundle `locales/` in either pyproject.toml's
      # package_data OR the Nix derivation. The actual model switch
      # itself works — it's only the acknowledgment text that's broken.
      # Tried patching via `package = ...overrideAttrs (postInstall …)`
      # but the Python venv is a separate uv2nix-built derivation that
      # the wrapper just references; we'd need to either copy the whole
      # venv (~hundreds of MB) or rebuild the inner uv2nix derivation.
      # Not worth the fight for a cosmetic fix. Upstream PR is the right
      # path — left untouched here.

      # `gh` is what the bundled github-* skills drive; without it on PATH
      # they fall back to raw `git` + API calls and lose features (PR review,
      # issue triage). `GH_TOKEN` (set above) is auto-picked-up by gh.
      extraPackages = [ pkgs.gh ];

      environmentFiles = [ config.sops.templates."hermes-agent.env".path ];

      environment = {
        SIGNAL_HTTP_URL = "http://127.0.0.1:${toString signalCfg.httpPort}";
        HERMES_HOME = "/var/lib/hermes/.hermes";
        # i18n locales patch — see `localesPatch` derivation in the `let`
        # block above for the why. sitecustomize.py auto-loads via the
        # PYTHONPATH and patches agent.i18n._locales_dir at startup.
        PYTHONPATH = "${localesPatch}/python";
        HERMES_LOCALES_DIR = "${localesPatch}/locales";
      };

      # Brief persona + tool-selection bias. The upstream module installs
      # SOUL.md into the working directory and Hermes reads it as part of
      # its system prompt every call. Inherited by delegated subagents.
      documents."SOUL.md" = ''
        You are Hermes — alex's personal AI assistant, reached via Signal.

        ## Model selection (alex's lever, not yours)

        Alex picks which model handles a conversation by sending
        slash commands in Signal. You don't manage this — you just
        execute whatever role you're configured for. The aliases:

        - `/model deep` — DeepSeek V4 Pro (default, reset after 2 h idle)
        - `/model opus` — Anthropic Claude Opus 4.7 Fast (top reasoning)
        - `/model pro`  — Google Gemini 3.1 Pro Preview (long context)
        - `/model think` — Kimi K2 Thinking (deep reasoning chains)
        - `/model qwen` — Qwen 3.6 35B A3B (cheap MoE alternative)
        - `/model flash` — Gemini 2.5 Flash Lite (cheapest cloud)
        - `/model local` — Gemma 4 8B on saruman's GPU (free, private)
        - `/model mac` — Gemma 4 26B A4B on alex's MacBook over tailnet
          (free, private, bigger than `local` but requires faramir online)

        When asked what model you are, answer truthfully based on the
        actual model serving this turn — don't claim to be a model
        that's not currently active.

        ## Tool guidance

        - For any question that references past notes, prior work, a project,
          or anything previously discussed, prefer **memory_search**. It is
          semantic (cosine similarity), ranked by relevance, and indexes BOTH
          the Obsidian vault (project='vault') AND bot-curated memories.
        - Use vault_search ONLY when you need an exact substring match in a
          specific file. memory_search is the default for "what did I/we
          write about X".
        - For Dataview-style queries — "list notes tagged X", "recent
          journal entries", "meetings in Work/ this month" — use
          **vault_query_frontmatter**. It filters by folder, frontmatter
          fields, tags (frontmatter `tags:` and inline `#tag` refs),
          mtime range, and filename glob, and returns `{path, mtime,
          frontmatter}` per match. Cheaper than reading every candidate
          file with vault_read.
        - Use vault_read / vault_list / vault_write for direct file ops once
          you already know the path (often discovered via memory_search hits
          which carry a `source` field of the form vault:<path>#<heading>).
        - For outbound Signal messages, signal_send_message queues only —
          you MUST present the pending entry to alex and wait for explicit
          confirmation before calling signal_pending_approve.
        - Calendar → **radicale-mcp** (`event_list`, `event_create`) the radicale General 
          calendar is the default write. Default query for both radicale calendars and shared gmail calendars.
          Only write for **gcal-mcp** when alex
          specifically mentions writing to shared Google calendar. Contacts → radicale-mcp. RSS
          feeds → miniflux-mcp.
        - For current/external info (news, docs, what-is-X-today), use
          **web_search** for a list of relevant snippets, then
          **web_extract** on the most useful URL for the full content.
          The 1000-searches-per-month budget is shared across all of
          alex's bot traffic — reach for memory_search and vault tools
          first when the answer is likely already in his notes.
        - **consult_expert** is a single-shot escalation tool useful
          when you (whatever model you currently are) need a one-off
          high-quality answer to a hard sub-question without changing
          the active conversation model. Alex's preferred path for
          full-conversation escalation is the `/model` slash above —
          consult_expert is for *sub-questions within a turn*. Pass
          `model="anthropic/claude-opus-4.7-fast"` for Opus,
          `"deepseek/deepseek-v4-pro"` for DeepSeek,
          `"google/gemini-3.1-pro-preview"` for Gemini Pro. Returns
          the expert's text answer for you to relay or summarize.

        Be concise. Signal messages are short by nature.
      '';

      settings = {
        # ─── Default model: DeepSeek V4 Pro via OR ────────────────────
        model = {
          provider = "openrouter";
          default = cfg.defaultModel;
          # 64K is hermes' floor. V4 Pro supports 1M+ context but we
          # cap so the compression math stays sane on Signal chats.
          context_length = 64000;
          # ZDR + US-HQ provider pinning for every default-model call.
          extra_body = {
            provider = {
              data_collection = "deny";
              only = cfg.delegateProviders;
              allow_fallbacks = true;
              sort = { by = "price"; };
            };
          };
        };

        # ─── /model aliases — what alex types in Signal ───────────────
        # `/model <alias>` switches the active model for the rest of
        # the session (until idle reset, daily reset, or another /model).
        # Aliases override hermes-agent's built-in MODEL_ALIASES table
        # to pin specific whitelisted slugs (the built-in "opus" alias
        # would resolve to claude-opus-4.7 which isn't on alex's OR
        # allow-list — only the -fast variant is).
        model_aliases = {
          # ── OpenRouter cloud aliases ──
          opus = {
            model = "anthropic/claude-opus-4.7-fast";
            provider = "openrouter";
          };
          flash = {
            # Cheapest cloud option ($0.10 in / $0.40 out per Mtok).
            # BYOK Gemini key in OR means inference bills against
            # alex's Google quota, not OR credit.
            model = "google/gemini-2.5-flash-lite";
            provider = "openrouter";
          };
          pro = {
            # Frontier Google when you need long-context (1M) or
            # complex multi-step reasoning without Opus pricing.
            model = "google/gemini-3.1-pro-preview";
            provider = "openrouter";
          };
          think = {
            # Extended-reasoning model. Use for genuinely hard
            # problems that benefit from "show your work" depth.
            model = "moonshotai/kimi-k2-thinking";
            provider = "openrouter";
          };
          qwen = {
            # Cheap MoE alternative to V4 Pro, comparable input cost
            # to flash but stronger reasoning for agentic tool use.
            model = "qwen/qwen3.6-35b-a3b";
            provider = "openrouter";
          };
          deep = {
            # Explicit alias for the default. Useful for typing
            # `/model deep` to switch back after using another alias.
            model = "deepseek/deepseek-v4-pro";
            provider = "openrouter";
          };

          # ── Local Ollama alias ──
          # `/model local` swaps to Gemma 4 8B on saruman's GTX 1080
          # Ti. Free, private (prompts never leave the box). Useful
          # for low-stakes chitchat or when you want to keep tokens
          # out of OR. Capabilities are limited at 8B — don't expect
          # the depth of V4 Pro.
          local = {
            model = cfg.localModel;
            provider = "custom";
            base_url = cfg.localBaseUrl;
            api_key = cfg.localApiKey;
          };

          # ── MacBook alias ──
          # `/model mac` hits LM Studio on faramir over tailnet.
          # Gemma 4 26B A4B (4B active, MoE) at MLX-native quality on
          # Apple Silicon. Bigger and stronger than the local 8B
          # Gemma on saruman, but only available when faramir is
          # online + LM Studio is running with the model loaded.
          mac = {
            model = cfg.macModel;
            provider = "custom";
            base_url = cfg.macBaseUrl;
            api_key = cfg.macApiKey;
          };
        };

        # ─── Fallback model ─────────────────────────────────────────
        # If the default V4 Pro call errors (rate-limit, provider
        # outage, transient 5xx), hermes auto-switches to V4 Flash on
        # OpenRouter. Different model so a model-level issue doesn't
        # cascade. Same US-HQ + ZDR pinning.
        fallback_model = {
          provider = "openrouter";
          model = "deepseek/deepseek-v4-flash";
          extra_body = {
            provider = {
              data_collection = "deny";
              only = cfg.delegateProviders;
              allow_fallbacks = true;
              sort = { by = "price"; };
            };
          };
        };

        # ─── Session reset ──────────────────────────────────────────
        # Signal sessions reset after `sessionIdleMinutes` of inactivity
        # — any `/model` override snaps back to the default V4 Pro at
        # that point. Hermes-agent also has a built-in 4 AM daily reset
        # that fires regardless of activity.
        reset_by_platform = {
          signal = {
            idle_minutes = cfg.sessionIdleMinutes;
          };
        };

        # Cap on tool-use iterations per Signal turn. Hard guardrail
        # against runaway cost when the model loops on a query (observed
        # 11+ vault_query/vault_read calls for a "today's notes" query
        # = ~$1 worth of input tokens at V4 Pro pricing because none of
        # our allowed ZDR providers support implicit caching, so every
        # iteration re-bills the full context). 10 is plenty for any
        # real personal-assistant query — anything beyond is the model
        # being inefficient.
        max_iterations = 10;

        # Compression keeps the conversation tail bounded.
        compression = {
          enabled = true;
          threshold = 0.12;
          target_ratio = 0.20;
        };

        # Web search + page extract via Tavily (1000 searches/mo free
        # tier). TAVILY_API_KEY is set in the env template above.
        web = {
          backend = "tavily";
        };

        # `web_search`/`web_extract` live in the `web` toolset; not in
        # the default `hermes-signal` preset. Extend so the active
        # model can hit the web when alex asks "what's current about X".
        platform_toolsets = {
          signal = [ "hermes-signal" "web" ];
        };

        # The `custom` provider handles the local-Ollama `/model local`
        # alias. Cold start (Gemma 4 loading 9.4 GB onto the GPU) can
        # take 10+ seconds, so widen the request timeout to 5 min and
        # re-enable the stale-call detector on a 15 min leash. OR
        # provider paths keep their snappier defaults.
        providers = {
          custom = {
            request_timeout_seconds = 300;
            stale_timeout_seconds = 900;
          };
        };
      };

      mcpServers = {
        agent-memory = {
          url = cfg.agentMemoryUrl;
          headers.Authorization = "Bearer \${HERMES_AGENT_MEMORY_TOKEN}";
          # Trim destructive ops out of the tool surface — operator can
          # still hit these via the dashboards / direct DB / sops. Saves
          # ~1-2 KB of tool descriptions per API call.
          tools.exclude = [ "memory_delete" "project_delete" ];
        };
        vault = {
          url = cfg.vaultUrl;
          headers.Authorization = "Bearer \${HERMES_VAULT_TOKEN}";
          # Keep vault_write available (LLM needs it for note creation /
          # journaling) but block the overwrite=true footgun pattern would
          # require a per-argument filter, which the upstream tool filter
          # doesn't support; we rely on the path-safety guard in vault-mcp.
        };
        signal = {
          url = cfg.signalMcpUrl;
          headers.Authorization = "Bearer \${HERMES_SIGNAL_MCP_TOKEN}";
          # signal_pending_deny is operator-side cleanup; the LLM should
          # never reject on its own behalf. Hide it.
          tools.exclude = [ "signal_pending_deny" ];
        };
        radicale = {
          url = cfg.radicaleMcpUrl;
          headers.Authorization = "Bearer \${HERMES_RADICALE_MCP_TOKEN}";
          # Calendar/contact deletion is destructive and rare; operator
          # uses the GUI client. Hide from the tool surface.
          tools.exclude = [ "event_delete" "task_delete" "contact_delete" ];
        };
        miniflux = {
          url = cfg.minifluxMcpUrl;
          headers.Authorization = "Bearer \${HERMES_MINIFLUX_MCP_TOKEN}";
          # feed_refresh is a manual op the LLM has no reason to invoke.
          # *_delete are destructive bulk-purges; keep operator-only.
          tools.exclude = [ "feed_refresh" "feed_delete" "category_delete" ];
        };
        gcal = {
          url = cfg.gcalMcpUrl;
          headers.Authorization = "Bearer \${HERMES_GCAL_MCP_TOKEN}";
          # Read-only MCP today (no event_create) — nothing to exclude.
        };
        escalator = {
          url = cfg.escalatorMcpUrl;
          headers.Authorization = "Bearer \${HERMES_ESCALATOR_MCP_TOKEN}";
          # Single-tool MCP — nothing to exclude.
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
      # PYTHONPATH and HERMES_LOCALES_DIR must be set at PROCESS SPAWN
      # time so Python's sitecustomize.py sees them during site init —
      # before any agent.i18n imports happen. The upstream module's
      # `services.hermes-agent.environment` option writes these into
      # `.env`, which is loaded later by hermes app code via
      # `load_hermes_dotenv()`. Too late for sitecustomize. Setting them
      # in systemd's own Environment= directive gets them into Python's
      # os.environ before Python even reads sys.argv.
      environment = {
        PYTHONPATH = "${localesPatch}/python";
        HERMES_LOCALES_DIR = "${localesPatch}/locales";
      };
      # Auto-restart whenever the rendered settings change. The upstream
      # module writes its config.yaml via the activation script, but it
      # doesn't bounce the running daemon on config-only edits — leading
      # to stale-config bugs (e.g., a model.extra_body change that needs
      # a process restart to take effect). Pinning restartTriggers to a
      # hash of the rendered settings closes that gap.
      restartTriggers = [
        (builtins.toJSON config.services.hermes-agent.settings)
        (builtins.toJSON config.services.hermes-agent.mcpServers)
        config.services.hermes-agent.documents."SOUL.md" or ""
        (builtins.toJSON config.services.hermes-agent.environment)
        # Cron-jobs.json's content goes through sops.templates which has
        # its own restartUnits hook (above), so this trigger only needs
        # to fire when the template SHAPE changes — schedule, model, etc.
        (builtins.toJSON cfg.morningBriefingSchedule)
        (builtins.toJSON cfg.morningBriefingModel)
      ];
      # ExecStartPre: hermes-agent calls signal-cli's HTTP RPC at startup
      # and exits 1 if the connection fails. systemd's After= only orders
      # *spawn*, not readiness. signal-cli's JVM takes 3-4 seconds before
      # its HTTP endpoint accepts connections, and hermes loses that race
      # on cold deploys. Poll until the daemon responds (or 30s timeout).
      serviceConfig.ExecStartPre = [
        (pkgs.writeShellScript "wait-for-signal-cli" ''
          set -eu
          url="http://127.0.0.1:${toString signalCfg.httpPort}/api/v1/rpc"
          for i in $(seq 1 30); do
            if ${pkgs.curl}/bin/curl -fsS -m 2 -X POST "$url" \
                 -H "Content-Type: application/json" \
                 -d '{"jsonrpc":"2.0","id":1,"method":"listAccounts","params":{}}' \
                 > /dev/null 2>&1; then
              exit 0
            fi
            sleep 1
          done
          echo "signal-cli HTTP RPC did not come up in 30s at $url" >&2
          exit 1
        '')
      ];
    };
  };
}
