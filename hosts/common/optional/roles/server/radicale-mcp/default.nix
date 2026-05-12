{ lib, pkgs, config, ... }:
let
  cfg = config.radicale-mcp;
  hosts = config.lab.hosts;
in
{
  options.radicale-mcp = {
    enable = lib.mkEnableOption "Radicale CalDAV/CardDAV MCP gateway";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4283;
      description = "TCP port the radicale-mcp gateway listens on. Tailnet IP only.";
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
      default = "radicale_mcp";
      description = "System user to run the service as.";
    };

    radicaleUrl = lib.mkOption {
      type = lib.types.str;
      default = "http://${hosts.phantom.ip}:5232/";
      description = ''
        Base URL of the Radicale instance. Defaults to the phantom-hosted
        instance on the LAN (also reachable via tailnet from saruman).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = "/var/lib/radicale-mcp";
      createHome = true;
      description = "radicale-mcp service user";
    };
    users.groups.${cfg.user} = { };

    sops.secrets.radicale_mcp_tokens = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };
    sops.secrets.radicale_mcp_user = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };
    sops.secrets.radicale_mcp_password = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };

    # Tiny EnvironmentFile rendered from sops at boot.
    sops.templates."radicale-mcp.env" = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      content = ''
        RADICALE_MCP_RADICALE_USER=${config.sops.placeholder.radicale_mcp_user}
        RADICALE_MCP_RADICALE_PASSWORD=${config.sops.placeholder.radicale_mcp_password}
      '';
    };

    environment.persistence."/persist".directories = [
      { directory = "/var/lib/radicale-mcp"; user = cfg.user; group = cfg.user; mode = "0750"; }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/radicale-mcp 0750 ${cfg.user} ${cfg.user} -"
    ];

    systemd.services.radicale-mcp = {
      description = "Radicale CalDAV/CardDAV MCP gateway";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        RADICALE_MCP_BIND_IP = cfg.bindIp;
        RADICALE_MCP_PORT = toString cfg.port;
        RADICALE_MCP_TOKENS_FILE = config.sops.secrets.radicale_mcp_tokens.path;
        RADICALE_MCP_RADICALE_URL = cfg.radicaleUrl;
      };

      serviceConfig = {
        ExecStart = "${pkgs.radicale-mcp}/bin/radicale-mcp";
        EnvironmentFile = config.sops.templates."radicale-mcp.env".path;
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/radicale-mcp" ];
      };
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
