{ lib, pkgs, config, ... }:
let
  cfg = config.prometheus-mcp;
  hosts = config.lab.hosts;
in
{
  options.prometheus-mcp = {
    enable = lib.mkEnableOption "Prometheus MCP gateway";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4287;
      description = "TCP port the prometheus-mcp gateway listens on. Tailnet IP only.";
    };

    bindIp = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = "IPv4 to bind. \"auto\" resolves tailnet IP at service start.";
    };

    tailnetInterface = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = "Interface on which to open the MCP port in the firewall.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "prometheus_mcp";
      description = "System user to run the service as.";
    };

    prometheusUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${hosts.atreides.ip}:9090";
      description = ''
        Base URL of the Prometheus instance (no trailing slash). Defaults
        to the atreides-hosted instance on the LAN.
      '';
    };

    alertmanagerUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = ''
        Optional Alertmanager base URL (no trailing slash). When set, the
        `alertmanager_*` MCP tools become callable. When null, those tools
        return a clear "not configured" error to the agent.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = "/var/lib/prometheus-mcp";
      createHome = true;
      description = "prometheus-mcp service user";
    };
    users.groups.${cfg.user} = { };

    sops.secrets.prometheus_mcp_tokens = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      restartUnits = [ "prometheus-mcp.service" ];
    };

    environment.persistence."/persist".directories = [
      { directory = "/var/lib/prometheus-mcp"; user = cfg.user; group = cfg.user; mode = "0750"; }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/prometheus-mcp 0750 ${cfg.user} ${cfg.user} -"
    ];

    # `prometheus-mcp --version` on PATH for operator convenience.
    environment.systemPackages = [ pkgs.prometheus-mcp ];

    systemd.services.prometheus-mcp = {
      description = "Prometheus + Alertmanager MCP gateway";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        PROMETHEUS_MCP_BIND_IP = cfg.bindIp;
        PROMETHEUS_MCP_PORT = toString cfg.port;
        PROMETHEUS_MCP_TOKENS_FILE = config.sops.secrets.prometheus_mcp_tokens.path;
        PROMETHEUS_MCP_PROM_URL = cfg.prometheusUrl;
      } // lib.optionalAttrs (cfg.alertmanagerUrl != null) {
        PROMETHEUS_MCP_AM_URL = cfg.alertmanagerUrl;
      };

      serviceConfig = {
        ExecStart = "${pkgs.prometheus-mcp}/bin/prometheus-mcp";
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/prometheus-mcp" ];
      };
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
