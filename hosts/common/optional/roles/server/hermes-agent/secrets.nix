{ lib, config, ... }:
let
  cfg = config.hermes-agent;
in
{
  config = lib.mkIf cfg.enable {
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
      # Same alex, single-identifier form (no UUID). hermes_allowlist
      # carries `+phone,uuid` for inbound-match flexibility, but
      # SIGNAL_HOME_CHANNEL needs ONE recipient or the standalone-send
      # fallback strips non-digits and concatenates the parts — caught
      # 2026-05-15 when the morning cron's signal delivery failed.
      hermes_self_number = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_agent_memory = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_vault = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_signal = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_radicale = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_miniflux = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_gcal = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_escalator = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_prometheus = { owner = "alex"; group = "hermes"; mode = "0400"; };
      future_hermes_email = { owner = "alex"; group = "hermes"; mode = "0400"; };
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
      # hermes-agent 0.17.0 removed the dashboard's `--insecure` unauthenticated
      # bind. A non-loopback bind (required — Traefik on atreides fronts it)
      # now needs a registered auth provider. We use the stdlib-scrypt basic
      # auth: username `alex`, precomputed password_hash below (reuses the same
      # plaintext as the Traefik htpasswd cred). `_secret` signs session cookies
      # so logins survive dashboard restarts. Read by the plugin from the
      # HERMES_DASHBOARD_BASIC_AUTH_* env vars in the template below.
      hermes_dashboard_basic_auth_password_hash = { owner = "alex"; group = "hermes"; mode = "0400"; };
      hermes_dashboard_basic_auth_secret = { owner = "alex"; group = "hermes"; mode = "0400"; };
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
      restartUnits = [ "hermes-agent.service" "hermes-dashboard.service" ];
      content = ''
        OPENROUTER_API_KEY=${config.sops.placeholder.openrouter_api_key}
        OPENROUTER_PROVISIONING_KEY=${config.sops.placeholder.openrouter_provisioning_key}
        TAVILY_API_KEY=${config.sops.placeholder.tavily_api_key}
        SIGNAL_ACCOUNT=${config.sops.placeholder.hermes_bot_account}
        SIGNAL_ALLOWED_USERS=${config.sops.placeholder.hermes_allowlist}
        # Where `hermes cron --deliver signal` jobs land. Must be a
        # SINGLE recipient identifier — `hermes_allowlist` carries
        # `+phone,uuid` for inbound matching and would get mangled by
        # the standalone-send fallback. The dedicated `hermes_self_number`
        # secret holds just `+phone`. Briefing arrives as a self-DM
        # (treated by Signal as "Note to Self").
        SIGNAL_HOME_CHANNEL=${config.sops.placeholder.hermes_self_number}
        HERMES_AGENT_MEMORY_TOKEN=${config.sops.placeholder.future_hermes_agent_memory}
        HERMES_VAULT_TOKEN=${config.sops.placeholder.future_hermes_vault}
        HERMES_SIGNAL_MCP_TOKEN=${config.sops.placeholder.future_hermes_signal}
        HERMES_RADICALE_MCP_TOKEN=${config.sops.placeholder.future_hermes_radicale}
        HERMES_MINIFLUX_MCP_TOKEN=${config.sops.placeholder.future_hermes_miniflux}
        HERMES_GCAL_MCP_TOKEN=${config.sops.placeholder.future_hermes_gcal}
        HERMES_ESCALATOR_MCP_TOKEN=${config.sops.placeholder.future_hermes_escalator}
        HERMES_PROMETHEUS_MCP_TOKEN=${config.sops.placeholder.future_hermes_prometheus}
        HERMES_EMAIL_MCP_TOKEN=${config.sops.placeholder.future_hermes_email}
        GH_TOKEN=${config.sops.placeholder.hermes_github_pat}
        # In-process plugins (hermes-plugin-intel) call miniflux's REST
        # API directly rather than going through miniflux-mcp's bearer
        # auth dance. We co-locate the upstream token here so the
        # plugin can read it from os.environ at handler time. The
        # sops secret itself is owned by alex:hermes mode 0440 — see
        # miniflux-mcp module.
        MINIFLUX_API_TOKEN=${config.sops.placeholder.miniflux_api_token}
        # Dashboard basic-auth (hermes-agent 0.17.0 auth gate). The dashboard
        # service loads this same env file; the dashboard_auth/basic plugin
        # reads these (env wins over config.yaml) and registers the provider,
        # letting it bind the tailnet interface for Traefik.
        HERMES_DASHBOARD_BASIC_AUTH_USERNAME=alex
        HERMES_DASHBOARD_BASIC_AUTH_PASSWORD_HASH=${config.sops.placeholder.hermes_dashboard_basic_auth_password_hash}
        HERMES_DASHBOARD_BASIC_AUTH_SECRET=${config.sops.placeholder.hermes_dashboard_basic_auth_secret}
      '';
    };
  };
}
