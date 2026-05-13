{ lib, pkgs, config, ... }:
let
  cfg = config.gcal-mcp;
in
{
  options.gcal-mcp = {
    enable = lib.mkEnableOption "Google Calendar MCP gateway (reuses existing google-workspace OAuth)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4286;
      description = "TCP port the gcal-mcp gateway listens on. Tailnet IP only.";
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
      default = "gcal_mcp";
      description = "System user to run the service as.";
    };

    googleTokenFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes/.hermes/google_token.json";
      description = ''
        Path to the persistent OAuth refresh-token JSON. Created by the
        bundled hermes-agent `google-workspace` skill setup flow; we
        reuse it here so no second OAuth dance is needed.
      '';
    };

    googleClientSecretFile = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/hermes/.hermes/google_client_secret.json";
      description = ''
        Path to the OAuth client-secret JSON (downloaded from Google
        Cloud Console). Rendered into HERMES_HOME by hermes-agent's
        sops template. Needed for refreshing expired access tokens.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      # Secondary membership in `hermes` lets us read the existing
      # google_token.json + google_client_secret.json files (mode 0440
      # on the hermes group after we adjust). The hermes user owns those
      # files via hermes-agent's sops + skill setup.
      extraGroups = [ "hermes" ];
      home = "/var/lib/gcal-mcp";
      createHome = true;
      description = "gcal-mcp service user";
    };
    users.groups.${cfg.user} = { };

    # Bearer tokens the MCP accepts from clients (hermes-agent).
    sops.secrets.gcal_mcp_tokens = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      restartUnits = [ "gcal-mcp.service" ];
    };

    environment.persistence."/persist".directories = [
      { directory = "/var/lib/gcal-mcp"; user = cfg.user; group = cfg.user; mode = "0750"; }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/gcal-mcp 0750 ${cfg.user} ${cfg.user} -"
    ];

    environment.systemPackages = [ pkgs.gcal-mcp ];

    systemd.services.gcal-mcp = {
      description = "Google Calendar MCP gateway";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        GCAL_MCP_BIND_IP = cfg.bindIp;
        GCAL_MCP_PORT = toString cfg.port;
        GCAL_MCP_TOKENS_FILE = config.sops.secrets.gcal_mcp_tokens.path;
        GCAL_MCP_GOOGLE_TOKEN_FILE = cfg.googleTokenFile;
        GCAL_MCP_GOOGLE_CLIENT_SECRET_FILE = cfg.googleClientSecretFile;
      };

      serviceConfig = {
        ExecStart = "${pkgs.gcal-mcp}/bin/gcal-mcp";
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = false;  # need read on /var/lib/hermes/.hermes/*
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/gcal-mcp" ];
        # ReadOnlyPaths captures the google credential files explicitly
        # so the sandbox makes them visible without granting broader
        # access. The hermes-group membership on the user controls
        # readability; this just ensures systemd's namespace doesn't
        # hide them.
        ReadOnlyPaths = [ "/var/lib/hermes/.hermes" ];
      };
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
