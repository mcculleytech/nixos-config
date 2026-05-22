{ lib, ... }:
let
  # Public OTLP/HTTP entrypoint terminated by Traefik on atreides; routes
  # to the collector at :4318 which fans out to Prometheus, Loki, Tempo.
  otelEndpoint = "https://otel.home.mcculley.tech";
in
{
  # Claude Code reads OTLP config from standard OTEL_* env vars at startup
  # (env wins over ~/.claude/settings.json for the same key). Declaring
  # them here makes every machine alex's home-manager owns auto-ship its
  # Claude Code telemetry to the homelab stack with no per-host setup.
  #
  # home.sessionVariables lands in ~/.config/home-manager/hm-session-vars.sh,
  # which the bash + zsh integrations source on shell init. That covers
  # `claude` invocations from a terminal. For desktop-launcher /
  # systemd-user-service launches, the vars also need to be in
  # systemd.user.sessionVariables — not wired yet because alex starts
  # Claude Code from a terminal today.
  home.sessionVariables = {
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
}
