{ config, lib, ... }:
{
  # ─── Alertmanager + ntfy routing ──────────────────────────────────────────
  # Alertmanager runs as a sub-service of Prometheus on this host (atreides),
  # receives fired alerts, groups/dedups them, and POSTs to ntfy on the same
  # host. ntfy understands Alertmanager's webhook JSON natively when called
  # with `?up=1` — renders alerts as readable notifications with title/body
  # rather than a raw JSON dump.
  #
  # Routing tiers (subscribe to each topic separately in the ntfy phone app):
  #   homelab-critical — severity=critical, fast page (10s wait, hourly nag)
  #   homelab-warnings — severity=warning, default tier
  #   homelab-info     — severity=info, low priority (mute-friendly)
  #
  # All three flow through ntfy on 127.0.0.1:2586 (same host, no Traefik /
  # TLS needed for the internal hop). Phone-side TLS is provided by Traefik
  # when subscribing to ntfy.<homelab_domain>.
  config = lib.mkIf config.prometheus-server.enable {
    services.prometheus.alertmanagers = [
      { static_configs = [ { targets = [ "127.0.0.1:9093" ]; } ]; }
    ];

    services.prometheus.alertmanager = {
      enable = true;
      port = 9093;
      configuration = {
        route = {
          receiver = "ntfy-warnings";
          group_by = [ "alertname" "instance" ];
          group_wait = "30s";
          group_interval = "5m";
          repeat_interval = "12h";
          routes = [
            {
              matchers = [ "severity=critical" ];
              receiver = "ntfy-critical";
              group_wait = "10s";
              repeat_interval = "1h";
            }
            {
              matchers = [ "severity=info" ];
              receiver = "ntfy-info";
              repeat_interval = "24h";
            }
          ];
        };
        receivers = [
          {
            name = "ntfy-critical";
            webhook_configs = [
              {
                url = "http://127.0.0.1:2586/homelab-critical?up=1&priority=urgent&tags=rotating_light";
                send_resolved = true;
              }
            ];
          }
          {
            name = "ntfy-warnings";
            webhook_configs = [
              {
                url = "http://127.0.0.1:2586/homelab-warnings?up=1&tags=warning";
                send_resolved = true;
              }
            ];
          }
          {
            name = "ntfy-info";
            webhook_configs = [
              {
                url = "http://127.0.0.1:2586/homelab-info?up=1&priority=low&tags=information_source";
                send_resolved = true;
              }
            ];
          }
        ];
      };
    };

    # Alertmanager state (silences, notification log) — survives reboots.
    # The nixpkgs alertmanager unit runs with DynamicUser=true + StateDirectory=alertmanager,
    # so systemd keeps the real state under /var/lib/private/alertmanager and exposes
    # /var/lib/alertmanager as a symlink. Persisting the symlink path as a real directory
    # makes StateDirectory setup fail with status=238/STATE_DIRECTORY. Persist the actual
    # private state dir as root:root 0700 — the same pattern the other DynamicUser services
    # here use (ntfy, tempo, otel-collector). systemd re-chowns the inner dir to the
    # per-boot dynamic UID on start.
    environment.persistence."/persist".directories = [
      { directory = "/var/lib/private/alertmanager"; user = "root"; group = "root"; mode = "0700"; }
    ];
  };
}
