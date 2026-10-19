{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.hermes-agent;
  signalCfg = config.signal-cli;

  # ─── i18n locales patch ───────────────────────────────────────────────────
  # Upstream's pyproject.toml + nix derivation don't ship `locales/` to the
  # installed wheel, so agent/i18n.py's `Path(__file__).parent.parent/locales`
  # path resolves to nothing and slash-command responses come back as raw
  # i18n keys (`gateway.model.switched`, etc.). We can't patch the venv
  # (uv2nix-built, deep in /nix/store), but we CAN inject a sitecustomize.py
  # via PYTHONPATH that monkey-patches `agent.i18n._locales_dir` at Python
  # startup — *before* any catalog lookup happens. Belt-and-suspenders the
  # env-var path so any code that respects it works too.
  #
  # Lives in this module (not pkgs/) because it depends on `inputs.hermes-agent`
  # which isn't part of the standard pkgs/callPackage signature.
  localesPatch = pkgs.runCommand "hermes-locales-patch" {} ''
    mkdir -p $out/locales $out/python
    cp -r ${inputs.hermes-agent}/locales/* $out/locales/
    cp ${./sitecustomize.py} $out/python/sitecustomize.py
  '';
in
{
  config = lib.mkIf cfg.enable {
    # ─── Upstream module configuration ─────────────────────────────────────
    services.hermes-agent = {
      enable = true;

      # See the "Run hermes-agent as alex" comment block in default.nix
      # for the full rationale.
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
        # Used by the bundled `obsidian` skill's path-resolution rule.
        # Without this, the skill falls back to `~/Documents/Obsidian Vault`
        # (doesn't exist here) and the model has been observed inventing
        # `$HERMES_HOME/vault` as a guess — patch/write tools then fail
        # silently. Our `obsidian-vault-policy` skill names the same
        # path; this env var pins the bundled skill to the same value.
        OBSIDIAN_VAULT_PATH = "/home/alex/obsidian/Barrow-Downs";
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
        # ─── Terminal cwd ─────────────────────────────────────────────
        # Upstream's nixos module still writes MESSAGING_CWD to .env at
        # activation (controlled by `services.hermes-agent.workingDirectory`)
        # but the runtime warns on every startup that MESSAGING_CWD is
        # deprecated unless `terminal.cwd` is *also* set explicitly here.
        # Point at the same path so the warning suppresses and the two
        # configs stay in lockstep.
        terminal.cwd = config.services.hermes-agent.workingDirectory;

        # ─── Default model: DeepSeek V4.1 Flash ──────────────────────
        model = {
          provider = "openrouter";
          default = cfg.defaultModel;
          # 64K is hermes' floor; cap so compression math stays sane on
          # Signal chats.
          context_length = 64000;
        };

        # ─── OpenRouter provider routing (applies to EVERY model) ────
        # This top-level key is the only provider-preference config
        # hermes 0.18 sends: gateway, cron and TUI all build the request's
        # `provider` object from it. The `model.extra_body.provider` /
        # `fallback_model.extra_body.provider` blocks we used before were
        # silently dropped — the 2026-10-15 request dumps carry no
        # `provider` field at all, which is why that 429 landed on
        # DeepInfra's shared pool. Because it's global, no `only` list:
        # it would block /model opus, gemini and auto.
        provider_routing = {
          # Exclude providers that retain/train on prompts.
          data_collection = "deny";
          # Only route to endpoints that support every request param
          # (tools, tool_choice) — matters for Flash/auto tool turns.
          require_parameters = true;
        };

        # ─── /model aliases — what alex types in Signal ───────────────
        # `/model <alias>` switches the active model for the rest of
        # the session (until idle reset, daily reset, or another /model).
        # Aliases override hermes-agent's built-in MODEL_ALIASES table
        # to pin specific slugs. Refreshed 2026-10-19 against OR's
        # /api/v1/models (claude-opus-4.7-fast had been retired).
        model_aliases = {
          # ── OpenRouter cloud aliases ──
          # Tracks `cfg.defaultModel` so `/model default` always returns to
          # whatever the gateway treats as the unset-session default —
          # change one knob, both stay aligned.
          default = {
            model = cfg.defaultModel;
            provider = "openrouter";
          };
          opus = {
            model = "anthropic/claude-opus-5.5";
            provider = "openrouter";
          };
          flash = {
            # Current-gen cheap/fast Google. BYOK Gemini key in OR means
            # inference bills against alex's Google quota, not OR credit.
            model = "google/gemini-3.8-flash";
            provider = "openrouter";
          };
          pro = {
            # Frontier Google when you need long-context or complex
            # multi-step reasoning without Opus pricing.
            model = "google/gemini-4-argon";
            provider = "openrouter";
          };
          gemini = {
            # Gemini 2.5 Flash via BYOK — the default until 2026-10-15.
            # Cheap, 1M context; good for long-document turns.
            model = "google/gemini-2.5-flash";
            provider = "openrouter";
          };
          deep = {
            # Harder multi-step reasoning when Flash falls short.
            # Switch with `/model deep`, return with `/model default`.
            model = "deepseek/deepseek-v4-pro";
            provider = "openrouter";
          };
          auto = {
            # OpenRouter Auto Router — picks a model per prompt, billed at
            # the chosen model's rate. Hermes can't send the router's
            # `plugins` options, so restrict candidates / cost tier on
            # OR's workspace Routing settings page instead.
            model = "openrouter/auto";
            provider = "openrouter";
          };
        };

        # ─── Fallback model ─────────────────────────────────────────
        # If the default DeepSeek call errors (rate-limit, provider
        # outage, transient 5xx), hermes auto-switches to Gemini 2.5
        # Flash. Different vendor on purpose: 2026-10-15 a DeepSeek-wide
        # 429 hit V4 Pro and the old V4 Flash fallback at the same time.
        fallback_model = {
          provider = "openrouter";
          model = "google/gemini-2.5-flash";
        };

        # ─── Session reset ──────────────────────────────────────────
        # Signal sessions reset after `sessionIdleMinutes` of inactivity
        # — any `/model` override snaps back to the default at
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

        # Disable bundled platform plugins we don't use. `google_chat`
        # ships in the wheel but its register() raises because the
        # Platform enum doesn't include `google_chat` in this hermes
        # version — every startup logs "Failed to load plugin
        # 'google_chat-platform': 'google_chat' is not a valid
        # Platform". The plugin itself isn't relevant to alex's setup
        # (Signal-only), so suppress it.
        plugins.disabled = [
          "google_chat-platform"
          "platforms/google_chat"
        ];
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
        prometheus = {
          url = cfg.prometheusMcpUrl;
          headers.Authorization = "Bearer \${HERMES_PROMETHEUS_MCP_TOKEN}";
          # Read-only by design — no exclusions needed. If/when we add
          # write-side tools (silence creation, etc.) revisit.
        };
        email = {
          url = cfg.emailMcpUrl;
          headers.Authorization = "Bearer \${HERMES_EMAIL_MCP_TOKEN}";
          # email_pending_deny is operator-side cleanup; the LLM should never
          # reject a queued send on its own behalf (mirrors signal). The
          # send path stays gated: email_send queues only, email_pending_approve
          # is the sole SMTP path — alex approves every outbound.
          tools.exclude = [ "email_pending_deny" ];
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
        # Upstream's `services.hermes-agent.environment.MESSAGING_CWD =
        # cfg.workingDirectory` triggers a "deprecated" warning at every
        # startup (the runtime mandates `terminal.cwd` in config.yaml
        # instead — set above). Clear it here so the env-var path is
        # gone; gateway/run.py falls back to `str(Path.home())` which
        # we then override by reading `terminal.cwd`.
        MESSAGING_CWD = lib.mkForce "";
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
        # hermes also resolves its own tailnet bind IP via `tailscale ip -4`
        # at start, so it loses the same tailscaled-restart race as the MCPs
        # (see mcp/default.nix for the full rationale). Gate on tailscale
        # readiness first, then wait on signal-cli below.
        "${pkgs.wait-tailnet-ip}/bin/wait-tailnet-ip"
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
