{ config, lib, ... }:
{
  # ─── Disk pressure alerts ────────────────────────────────────────────────
  # PromQL rules evaluated against node_exporter metrics. Routed by severity:
  #   critical → ntfy-critical (10s page, urgent priority, hourly nag)
  #   warning  → ntfy-warnings (default tier)
  #
  # Both rules filter to real filesystems only (skip tmpfs / overlay / fuse)
  # and key on `mountpoint="/"` since the encryptedRoot is mounted there on
  # every host. saruman's /, /nix, /persist all map to the same filesystem,
  # so a single mount-point matcher avoids triple-firing.
  config = lib.mkIf config.prometheus-server.enable {
    services.prometheus.rules = [
      (builtins.toJSON {
        groups = [
          {
            name = "disk-pressure";
            interval = "1m";
            rules = [
              {
                alert = "DiskCritical";
                # Below 10 GB the system is in trouble — recovery becomes hard
                # (see 2026-05-26 incident where Nix daemon crashed before we
                # could free space).
                expr = ''node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay|fuse.*"} < 10e9'';
                "for" = "15m";
                labels = { severity = "critical"; };
                annotations = {
                  summary = "Disk critical on {{ $labels.instance }}";
                  description = "{{ $labels.mountpoint }} on {{ $labels.instance }} has only {{ $value | humanize1024 }} free — recovery margin is thin.";
                };
              }
              {
                alert = "DiskFillingFast";
                # Linear regression over the last 6h, projected 24h forward.
                # Fires while there's still time to act — the 2026-05-26
                # failure mode would have tripped this hours before crash.
                expr = ''predict_linear(node_filesystem_avail_bytes{mountpoint="/",fstype!~"tmpfs|overlay|fuse.*"}[6h], 24*3600) < 0'';
                "for" = "1h";
                labels = { severity = "warning"; };
                annotations = {
                  summary = "{{ $labels.instance }} disk will fill within 24h";
                  description = "Linear extrapolation of {{ $labels.mountpoint }} free space on {{ $labels.instance }} predicts hitting zero within 24h. Investigate before recovery becomes hard.";
                };
              }
            ];
          }
        ];
      })
    ];
  };
}
