{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.hermes-agent;
  signalCfg = config.signal-cli;
  # Tailnet IP of the host running both Hermes and the MCP servers. The MCPs
  # bind tailnet-only (resolved at service start via `tailscale ip -4`), so
  # even from saruman itself the path is tailnet0, not loopback. Pulled from
  # hosts-data.nix so we have one place to update if the IP ever changes.
  mcpHost = config.lab.hosts.saruman.tailnetIp;

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
    cp ${./sitecustomize.py} $out/python/sitecustomize.py
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
    # escalator-mcp). See `users.groups.hermes` below.

    # The `hermes` group survives the user removal — it stays as a
    # shared-secret group: alex + escalator_mcp + gcal_mcp users are
    # all members, secrets are mode 0440 group=hermes.
    users.groups.hermes = { };
    # Add alex to the hermes group so the service (running as alex) can
    # read its own sops-rendered EnvironmentFile (mode 0400 owner=alex)
    # AND the shared mode-0440 group=hermes secrets the MCPs depend on.
    users.users.alex.extraGroups = [ "hermes" ];

    # ─── sops scalars (values added via `sops secrets/main.yaml`) ───────────
    sops.secrets = {
      # The single key that fronts ALL model traffic. A runtime sub-key
      # created out-of-band against the OR provisioning key with a one-shot
      # provisioning key (which is never stored). Sub-key carries a hard
      # monthly credit cap. The user's Gemini key is registered in OR
      # as BYOK so tier-1 inference still bills against the Google quota.
      # Shared with escalator-mcp (which also needs to make OR calls).
      # mode 0440 so anyone in the hermes group can read; escalator-mcp's
      # service user joins the hermes group via its module.
      openrouter_api_key = { owner = "alex"; group = "hermes"; mode = "0440"; };
      # Management key for OR — different from the inference sub-key
      # above. /credits accepts the inference key, but /activity (the
      # per-request log used for spend reporting) requires the master
      # provisioning key. The /spend plugin reads this; until alex
      # replaces the placeholder via `sops secrets/main.yaml`, the
      # plugin's per-model breakdown gracefully degrades to "not
      # configured".
      openrouter_provisioning_key = {
        owner = "alex";
        group = "hermes";
        mode = "0440";
      };
      # Tavily for web_search / web_extract tools. Free tier = 1000
      # searches/mo at https://app.tavily.com — plenty for personal use.
      tavily_api_key = { owner = "alex"; group = "hermes"; mode = "0400"; };
      hermes_bot_account = { owner = "alex"; group = "hermes"; mode = "0400"; };
      hermes_allowlist = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_agent_memory = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_vault = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_signal = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_radicale = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_miniflux = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_gcal = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_escalator = { owner = "alex"; group = "hermes"; mode = "0400"; };
      hermes_github_pat = { owner = "alex"; group = "hermes"; mode = "0400"; };
      # Rendered directly into HERMES_HOME at the path the google-workspace
      # skill's setup.py expects (hard-coded `${HERMES_HOME}/google_client_secret.json`).
      # Mode 0440 (group-readable) so gcal-mcp's service user, which has
      # secondary membership in the `hermes` group, can read it for
      # token refresh.
      hermes_google_client_secret = {
        owner = "alex";
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
      "d /var/lib/hermes/.hermes 0750 alex hermes -"
      "d /var/lib/hermes/.hermes/cron 2770 alex hermes -"
      # The skill writes google_token.json with the running user's
      # default umask (typically 0600). Force group-readable so gcal-mcp
      # can read it for token refreshes. tmpfiles's `z` mode adjusts an
      # EXISTING file without creating it.
      "z /var/lib/hermes/.hermes/google_token.json 0640 alex hermes -"
    ];

    # One-shot state migration: when we flip the service user from the
    # dedicated `hermes` system user to `alex`, every file under
    # /var/lib/hermes that was created by the old user is still owned by
    # uid=hermes:gid=hermes. With createUser = false, NixOS will tear down
    # the hermes USER on this activation, orphaning those files (numeric
    # uid with no name). Walk the tree and chown by subtree:
    #   • /var/lib/hermes/.hermes        → alex:hermes  (hermes-agent state)
    #   • /var/lib/hermes/workspace      → alex:hermes  (agent workspace)
    #   • /var/lib/hermes/signal-cli     → alex:users   (signal-cli state;
    #     narrow group, not shared with the MCPs)
    # The parent /var/lib/hermes itself is alex:hermes (tmpfiles-managed).
    # Idempotent: subsequent runs are no-ops. Removable after the first
    # successful deploy.
    system.activationScripts.hermes-state-chown = {
      text = ''
        if [ -d /var/lib/hermes ]; then
          ${pkgs.coreutils}/bin/chown alex:hermes /var/lib/hermes || true
          for sub in .hermes workspace; do
            if [ -d /var/lib/hermes/$sub ]; then
              ${pkgs.coreutils}/bin/chown -R alex:hermes /var/lib/hermes/$sub || true
            fi
          done
          if [ -d /var/lib/hermes/signal-cli ]; then
            ${pkgs.coreutils}/bin/chown -R alex:users /var/lib/hermes/signal-cli || true
          fi
        fi
      '';
      deps = [ "users" "groups" ];
    };

    # ─── EnvironmentFile rendered from sops at boot ────────────────────────
    # Hermes reads every secret it needs from this single file. No plaintext
    # ever lives in the Nix store.
    sops.templates."hermes-agent.env" = {
      owner = "alex";
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
        OPENROUTER_PROVISIONING_KEY=${config.sops.placeholder.openrouter_provisioning_key}
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
        # In-process plugins (hermes-plugin-intel) call miniflux's REST
        # API directly rather than going through miniflux-mcp's bearer
        # auth dance. We co-locate the upstream token here so the
        # plugin can read it from os.environ at handler time. The
        # sops secret itself is owned by alex:hermes mode 0440 — see
        # miniflux-mcp module.
        MINIFLUX_API_TOKEN=${config.sops.placeholder.miniflux_api_token}
      '';
    };

    # ─── Upstream module configuration ─────────────────────────────────────
    services.hermes-agent = {
      enable = true;

      # See the "Run hermes-agent as alex" comment block above for why.
      user = "alex";
      group = "hermes";
      createUser = false;  # alex declared elsewhere; hermes group above.

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
      #
      # `claude` (from sadjow/claude-code-nix flake input) is on PATH so the
      # bundled claude-code skill can shell out for deep coding / repo-aware
      # tasks. Since the service runs as alex, auth state resolves to
      # /home/alex/.claude/ natively — no sudo, no auth copy needed.
      extraPackages = [
        pkgs.gh
        inputs.claude-code.packages.${pkgs.system}.default
      ];

      # Directory-style plugins — symlinked into $HERMES_HOME/plugins/<name>/
      # and auto-discovered by hermes on startup. See pkgs/hermes-plugin-intel/
      # for the source. Pure-Python, in-process — no separate systemd unit,
      # no bearer-token dance, just a slash command handler.
      extraPlugins = [
        pkgs.hermes-plugin-intel
        pkgs.hermes-plugin-today
        pkgs.hermes-plugin-spend
      ];

      environmentFiles = [ config.sops.templates."hermes-agent.env".path ];

      environment = {
        SIGNAL_HTTP_URL = "http://127.0.0.1:${toString signalCfg.httpPort}";
        HERMES_HOME = "/var/lib/hermes/.hermes";
        # MCP endpoints for in-process plugins (hermes-plugin-today,
        # etc.). The MCPs bind to the tailnet IP only, so the plugin
        # needs the resolved URL — not the `saruman` hostname which
        # routes to the LAN IP. Same values hermes' own mcpServers.*
        # config uses, just reflected into the env so plugins don't
        # have to parse config.yaml.
        HERMES_PLUGIN_RADICALE_URL = cfg.radicaleMcpUrl;
        HERMES_PLUGIN_GCAL_URL = cfg.gcalMcpUrl;
        # Override the upstream module's HOME=/var/lib/hermes default so
        # claude / gh / other bundled-skill tools resolve their auth state
        # in /home/alex/{.claude,.config/gh}/ — the user's normal locations.
        # HERMES_HOME stays explicit so hermes still stores its state in
        # /var/lib/hermes/.hermes, NOT in /home/alex/.hermes.
        HOME = "/home/alex";
        # i18n locales patch — see `localesPatch` derivation in the `let`
        # block above for the why. sitecustomize.py auto-loads via the
        # PYTHONPATH and patches agent.i18n._locales_dir at startup.
        PYTHONPATH = "${localesPatch}/python";
        HERMES_LOCALES_DIR = "${localesPatch}/locales";
      };

      # Persona + tool-selection bias for the in-context system prompt.
      # Lives in a sibling SOUL.md so it can be edited as plain markdown
      # (linting, preview, no nix heredoc escape pain). Upstream installs
      # the document into the working directory; hermes reads it on every
      # call and inherited by delegated subagents.
      documents."SOUL.md" = builtins.readFile ./SOUL.md;

      settings = {
        # ─── Default model: Gemini 2.5 Flash via OR BYOK ──────────────
        model = {
          provider = "openrouter";
          default = cfg.defaultModel;
          # 64K is hermes' floor; Gemini Flash supports 1M context but we
          # cap so compression math stays sane on Signal chats.
          context_length = 64000;
          # Pin OR to the google-ai-studio provider so BYOK fires
          # (otherwise OR could route via google-vertex which doesn't
          # use alex's Google AI Studio key). data_collection=deny is a
          # belt-and-suspenders ZDR check — the actual retention
          # guarantee comes from alex's Google paid tier. allow_fallbacks
          # off → if Google errors, we deliberately fall through to
          # `fallback_model` below (deepseek-v4-flash on ZDR US-HQ
          # providers) rather than silently routing to a non-BYOK
          # Google path that would bill OR credit.
          extra_body = {
            provider = {
              data_collection = "deny";
              only = [ "google-ai-studio" ];
              allow_fallbacks = false;
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

        # User-installed plugins are opt-in via this allow-list (bundled
        # backends auto-load, ours doesn't). Registry key for a flat
        # extraPlugins package is the symlink directory name —
        # nix-managed-<pname> — but the manifest's `name` field is also
        # accepted as a fallback. We list both to be safe.
        plugins.enabled = [
          "intel" "nix-managed-hermes-plugin-intel"
          "today" "nix-managed-hermes-plugin-today"
          "spend" "nix-managed-hermes-plugin-spend"
        ];

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
        # The upstream module hardcodes `HOME = cfg.stateDir` on the
        # systemd unit (line ~874 in nixosModules.nix) so subprocesses
        # spawned by hermes inherit HOME=/var/lib/hermes. That breaks
        # claude / gh / etc., which look for auth state under
        # ~/.claude and ~/.config/gh. We're running as alex; point HOME
        # at /home/alex so those tools resolve to alex's real auth.
        # lib.mkForce because the upstream module sets the same key
        # without mkDefault.
        HOME = lib.mkForce "/home/alex";
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
        # Plugin packages (e.g. hermes-plugin-intel) — without this trigger,
        # a plugin source-code change deploys to disk but the running
        # hermes process keeps the old code loaded. Hash of the package
        # list catches both content edits and add/remove churn.
        (builtins.toJSON (map toString config.services.hermes-agent.extraPlugins))
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
