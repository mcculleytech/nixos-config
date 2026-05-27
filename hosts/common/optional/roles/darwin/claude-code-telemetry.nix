{ config, lib, ... }:
let
  otelEndpoint = "https://otel.home.mcculley.tech";
in
{
  options.lab.claude-code-telemetry.enable = lib.mkOption {
    type = lib.types.bool;
    default = true;
    description = ''
      nix-darwin sibling of hosts/common/optional/claude-code-telemetry.nix.
      Ships Claude Code CLI telemetry to the homelab OTEL collector
      (metrics → Prometheus, logs → Loki, traces → Tempo).

      macOS has no PAM session env injection, so we use
      environment.variables — written to /etc/zshenv and /etc/bashrc, which
      zsh/bash source for every shell (including non-interactive ones).
      Sufficient for a terminal-launched CLI like Claude Code; not enough
      for GUI/Spotlight-launched apps (would need launchd.user.envVariables
      for that).
    '';
  };

  config = lib.mkIf config.lab.claude-code-telemetry.enable {
    environment.variables = {
      CLAUDE_CODE_ENABLE_TELEMETRY = "1";

      OTEL_METRICS_EXPORTER = "otlp";
      OTEL_LOGS_EXPORTER    = "otlp";
      OTEL_TRACES_EXPORTER  = "otlp";

      # Include the actual prompt text on user_prompt log events. Default
      # is redacted (Claude Code only emits prompt length + session id).
      # Safe here because the OTEL endpoint is single-tenant homelab.
      OTEL_LOG_USER_PROMPTS = "1";

      OTEL_EXPORTER_OTLP_PROTOCOL = "http/protobuf";
      OTEL_EXPORTER_OTLP_ENDPOINT = otelEndpoint;

      # See note in the NixOS sibling: Claude Code exports metric deltas by
      # default but Prometheus's OTLP receiver wants cumulative. Set the
      # client preference to avoid the collector's deltatocumulative
      # conversion entirely.
      OTEL_EXPORTER_OTLP_METRICS_TEMPORALITY_PREFERENCE = "cumulative";
    };
  };
}
