{ lib, pkgs, config, ... }:
let
  cfg = config.signal-mcp;
  signalCfg = config.signal-cli;
in
{
  options.signal-mcp = {
    enable = lib.mkEnableOption "Signal outbound MCP gateway (with mandatory approval gate)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4282;
      description = "TCP port the signal-mcp gateway listens on. Tailnet IP only.";
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
      default = "signal_mcp";
      description = "System user to run the service as.";
    };

    botAccount = lib.mkOption {
      type = lib.types.str;
      description = ''
        Bot's Signal E.164 number, used as the sending account in signal-cli RPC.
        Sourced from sops at runtime via the sops template; this option is here
        for documentation — the actual value is injected via env var.
      '';
      default = "set-via-sops-template";
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = "/var/lib/signal-mcp";
      createHome = true;
      description = "signal-mcp service user";
    };
    users.groups.${cfg.user} = { };

    # Bearer tokens for MCP clients (Hermes, Claude on faramir, etc.).
    sops.secrets.signal_mcp_tokens = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };

    # Persisted SQLite pending DB.
    environment.persistence."/persist".directories = [
      { directory = "/var/lib/signal-mcp"; user = cfg.user; group = cfg.user; mode = "0750"; }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/signal-mcp 0750 ${cfg.user} ${cfg.user} -"
    ];

    systemd.services.signal-mcp = {
      description = "Signal outbound MCP gateway (with approval gate)";
      after = [
        "network-online.target"
        "tailscaled.service"
        "signal-cli.service"
      ];
      wants = [ "network-online.target" "tailscaled.service" ];
      requires = [ "signal-cli.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        SIGNAL_MCP_BIND_IP = cfg.bindIp;
        SIGNAL_MCP_PORT = toString cfg.port;
        SIGNAL_MCP_TOKENS_FILE = config.sops.secrets.signal_mcp_tokens.path;
        SIGNAL_MCP_SIGNAL_HTTP_URL = "http://127.0.0.1:${toString signalCfg.httpPort}";
        SIGNAL_MCP_DB = "/var/lib/signal-mcp/pending.db";
      };

      # Bot account comes from the same sops scalar Hermes uses (hermes_bot_account).
      # Sops renders a tiny EnvironmentFile dedicated to signal-mcp.
      serviceConfig.EnvironmentFile = config.sops.templates."signal-mcp.env".path;

      serviceConfig = {
        ExecStart = "${pkgs.signal-mcp}/bin/signal-mcp";
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/signal-mcp" ];
      };
    };

    # Render a small EnvironmentFile containing the bot account number.
    # Reuses the existing hermes_bot_account scalar — same value either way.
    sops.templates."signal-mcp.env" = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      content = ''
        SIGNAL_MCP_SIGNAL_ACCOUNT=${config.sops.placeholder.hermes_bot_account}
      '';
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
