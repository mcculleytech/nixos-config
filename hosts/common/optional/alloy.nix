{ config, lib, pkgs, ... }:
let
  cfg = config.lab.alloy;
  lokiEndpoint = "http://${cfg.lokiHost}:3100/loki/api/v1/push";

  # Alloy config (River syntax). Reads systemd-journald and ships to the
  # central Loki on atreides. Hostname is taken from the agent at runtime
  # via `constants.hostname` so this same file works on every host.
  alloyConfig = pkgs.writeText "config.alloy" ''
    // Tail journald and forward directly to Loki. relabel rules are
    // pulled from a rules-only `loki.relabel` (with empty forward_to) —
    // canonical Alloy pattern for promoting journald `__journal_*`
    // fields into stream labels.
    loki.source.journal "system" {
      forward_to    = [loki.write.atreides.receiver]
      labels        = {
        host = constants.hostname,
        job  = "systemd-journal",
      }
      relabel_rules = loki.relabel.journal.rules
    }

    // Promote a small set of journald hidden fields to visible Loki
    // labels. Keep this list tight — every label is a cardinality bomb
    // risk. Other journald fields stay searchable via LogQL parsers on
    // the log line itself.
    loki.relabel "journal" {
      forward_to = []
      rule {
        source_labels = ["__journal__systemd_unit"]
        target_label  = "unit"
      }
      rule {
        source_labels = ["__journal_priority_keyword"]
        target_label  = "level"
      }
      rule {
        source_labels = ["__journal__transport"]
        target_label  = "transport"
      }
    }

    loki.write "atreides" {
      endpoint {
        url = "${lokiEndpoint}"
      }
    }
  '';
in
{
  options.lab.alloy = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Run Grafana Alloy as a journald → Loki log shipper.";
    };

    lokiHost = lib.mkOption {
      type = lib.types.str;
      default = config.lab.hosts.atreides.ip;
      description = ''
        Address (IP or hostname) of the central Loki instance the shipper
        should push to. Defaults to atreides's nix-subnet LAN IP. Override
        per-host when a box can't reach that — e.g. vader on the DMZ
        subnet uses atreides's tailnet IP instead.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    services.alloy = {
      enable = true;
      configPath = alloyConfig;
    };

    # Journal read access comes for free — the upstream module already
    # adds `systemd-journal` to SupplementaryGroups in the service unit.

    # State is deliberately *not* persisted: tried the tempo/otel pattern
    # of persisting /var/lib/private/alloy, but systemd's StateDirectory
    # chown for the DynamicUser fails against the bind-mounted /persist
    # path (status=238/STATE_DIRECTORY on every restart). Losing the
    # journal cursor on reboot just means re-shipping a small window of
    # recent entries to Loki; Loki dedupes on identical timestamp+labels
    # so the worst case is some redundant ingest, not duplicated lines.
  };
}
