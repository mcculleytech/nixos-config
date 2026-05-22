{ config, lib, ... }:
let
  # Public OTLP/HTTP entrypoint terminated by Traefik on atreides; routes
  # to the collector at :4318 which fans out to Prometheus, Loki, Tempo.
  otelEndpoint = "https://otel.home.mcculley.tech";
in
{
  options.lab.claude-code-telemetry.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      Ship Claude Code CLI telemetry to the homelab OTEL collector
      (metrics → Prometheus, logs → Loki, traces → Tempo). Sets the
      standard OTEL_* env vars + CLAUDE_CODE_ENABLE_TELEMETRY via PAM
      session, so every login (terminal, SSH, desktop launcher,
      systemd-user) inherits them — no shell-init dependency.
    '';
  };

  config = lib.mkIf config.lab.claude-code-telemetry.enable {
    # environment.sessionVariables is written to /etc/profile.d but more
    # importantly is exported into the PAM session at login time, so
    # processes launched outside an interactive shell (desktop entries,
    # systemd-user services, IDE integrations) still see the vars. The
    # earlier home.sessionVariables route relied on bash/zsh sourcing
    # hm-session-vars.sh — broke for any non-shell launch.
    environment.sessionVariables = {
      CLAUDE_CODE_ENABLE_TELEMETRY = "1";

      OTEL_METRICS_EXPORTER = "otlp";
      OTEL_LOGS_EXPORTER    = "otlp";
      OTEL_TRACES_EXPORTER  = "otlp";

      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
      OTEL_EXPORTER_OTLP_ENDPOINT = otelEndpoint;

      # Claude Code (and most OTel SDKs) export metric deltas by default;
      # Prometheus's OTLP receiver expects cumulative. The collector has
      # `deltatocumulative` as a backstop processor, but setting the
      # client preference avoids the conversion entirely. See
      # hosts/common/optional/roles/server/otel-collector.nix.
      OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";
    };
  };
}
