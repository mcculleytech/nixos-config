{ lib, pkgs, config, inputs, ... }:
let
  cfg = config.hermes-dashboard;
  # Build the hermes-agent package (so we can reference $out/share/hermes-agent/web_dist).
  hermesAgent = inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default;
in
{
  options.hermes-dashboard = {
    enable = lib.mkEnableOption "Hermes web dashboard (Vite/React) — exposes admin UI behind reverse proxy";

    port = lib.mkOption {
      type = lib.types.port;
      default = 9119;
      description = "TCP port the dashboard listens on.";
    };

    bindIp = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = ''
        IPv4 to bind to. "auto" resolves saruman's tailnet IP at service start.
        The dashboard is unauthenticated at the application layer — auth is
        provided by the upstream reverse proxy (Traefik basicAuth + IP allowlist).
      '';
    };

    tailnetInterface = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = "Interface on which to open the dashboard port in the firewall.";
    };

    tui = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = ''
        Embed the in-browser Chat tab (proxies a `hermes --tui` session over
        WebSocket). Convenient for desktop use; the WebSocket inherits the
        Traefik basicAuth + IP allowlist gates.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    systemd.services.hermes-dashboard = {
      description = "Hermes web dashboard (admin UI behind Traefik)";
      after = [
        "network-online.target"
        "tailscaled.service"
        "hermes-agent.service"
      ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      # Reuse Hermes's existing EnvironmentFile (Anthropic key, HERMES_*).
      # The dashboard reads the same .env that the gateway does.
      serviceConfig.EnvironmentFile = config.sops.templates."hermes-agent.env".path;

      environment = {
        HERMES_HOME = "/var/lib/hermes/.hermes";
        # Pin the web dist explicitly so --skip-build serves the right files.
        HERMES_WEB_DIST = "${hermesAgent}/share/hermes-agent/web_dist";
      } // lib.optionalAttrs cfg.tui {
        HERMES_DASHBOARD_TUI = "1";
      };

      # `hermes dashboard` defaults to 127.0.0.1; we need it on the tailnet
      # interface so Traefik on atreides can reach it. The Python code expects
      # an explicit `--insecure` opt-in when binding to non-localhost (the
      # flag is about the dashboard itself having no auth — Traefik provides
      # both basicAuth AND an IP allowlist before forwarding here).
      script = ''
        set -eu
        if [ "${cfg.bindIp}" = "auto" ]; then
          bind=$(tailscale ip -4 | head -n1)
        else
          bind="${cfg.bindIp}"
        fi
        exec ${hermesAgent}/bin/hermes dashboard \
          --host "$bind" \
          --port ${toString cfg.port} \
          --insecure \
          --skip-build \
          --no-open
      '';

      serviceConfig = {
        User = "hermes";
        Group = "hermes";
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = false;  # HERMES_HOME lives under /var/lib/hermes
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/hermes" ];
      };
    };

    # Open the dashboard port to Traefik on atreides over the tailnet.
    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
