{ lib, pkgs, config, ... }:
let
  cfg = config.miniflux-mcp;
  hosts = config.lab.hosts;
in
{
  options.miniflux-mcp = {
    enable = lib.mkEnableOption "Miniflux RSS reader MCP gateway";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4284;
      description = "TCP port the miniflux-mcp gateway listens on. Tailnet IP only.";
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
      default = "miniflux_mcp";
      description = "System user to run the service as.";
    };

    minifluxUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${hosts.phantom.ip}:8080";
      description = ''
        Base URL of the Miniflux instance (no trailing /v1). Defaults to the
        phantom-hosted instance on the LAN (also reachable via tailnet).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = "/var/lib/miniflux-mcp";
      createHome = true;
      description = "miniflux-mcp service user";
    };
    users.groups.${cfg.user} = { };

    sops.secrets.miniflux_mcp_tokens = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };
    sops.secrets.miniflux_api_token = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };

    # Render an EnvironmentFile with just the upstream Miniflux API token.
    # Pattern mirrors radicale-mcp.env / signal-mcp.env from earlier modules.
    sops.templates."miniflux-mcp.env" = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      content = ''
        MINIFLUX_MCP_MINIFLUX_TOKEN=${config.sops.placeholder.miniflux_api_token}
      '';
    };

    environment.persistence."/persist".directories = [
      { directory = "/var/lib/miniflux-mcp"; user = cfg.user; group = cfg.user; mode = "0750"; }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/miniflux-mcp 0750 ${cfg.user} ${cfg.user} -"
    ];

    systemd.services.miniflux-mcp = {
      description = "Miniflux RSS reader MCP gateway";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        MINIFLUX_MCP_BIND_IP = cfg.bindIp;
        MINIFLUX_MCP_PORT = toString cfg.port;
        MINIFLUX_MCP_TOKENS_FILE = config.sops.secrets.miniflux_mcp_tokens.path;
        MINIFLUX_MCP_MINIFLUX_URL = cfg.minifluxUrl;
      };

      serviceConfig = {
        ExecStart = "${pkgs.miniflux-mcp}/bin/miniflux-mcp";
        EnvironmentFile = config.sops.templates."miniflux-mcp.env".path;
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/miniflux-mcp" ];
      };
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
