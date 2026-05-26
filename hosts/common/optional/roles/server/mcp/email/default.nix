{ lib, pkgs, config, ... }:
let
  cfg = config.email-mcp;
in
{
  options.email-mcp = {
    enable = lib.mkEnableOption "IMAP/SMTP email MCP gateway (with mandatory send approval gate)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4288;
      description = "TCP port the email-mcp gateway listens on. Tailnet IP only.";
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
      default = "email_mcp";
      description = "System user to run the service as.";
    };

    imapAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:1144";
      description = ''
        IMAP address of the local Proton Mail Bridge (STARTTLS, self-signed
        cert — connection uses InsecureSkipVerify, acceptable loopback-only).
      '';
    };

    smtpAddr = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1:1026";
      description = ''
        SMTP submission address of the local Proton Mail Bridge (STARTTLS,
        self-signed cert). Reached ONLY by email_pending_approve.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      home = "/var/lib/email-mcp";
      createHome = true;
      description = "email-mcp service user";
    };
    users.groups.${cfg.user} = { };

    # Bearer tokens for MCP clients (Hermes, Claude on faramir, etc.).
    sops.secrets.email_mcp_tokens = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      restartUnits = [ "email-mcp.service" ];
    };

    # Upstream Bridge IMAP/SMTP credentials. IMAP and SMTP share the same
    # user/pass on Proton Bridge. These feed the env template below;
    # restartUnits lives on the template (re-rendered when either changes).
    sops.secrets.proton_bridge_user = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };
    sops.secrets.proton_bridge_pass = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
    };

    # Tiny EnvironmentFile rendered from sops at boot.
    sops.templates."email-mcp.env" = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      restartUnits = [ "email-mcp.service" ];
      content = ''
        EMAIL_MCP_IMAP_USER=${config.sops.placeholder.proton_bridge_user}
        EMAIL_MCP_IMAP_PASS=${config.sops.placeholder.proton_bridge_pass}
      '';
    };

    # Persisted SQLite pending DB.
    environment.persistence."/persist".directories = [
      { directory = "/var/lib/email-mcp"; user = cfg.user; group = cfg.user; mode = "0750"; }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/email-mcp 0750 ${cfg.user} ${cfg.user} -"
    ];

    # `email-mcp --version` on PATH for operator convenience.
    environment.systemPackages = [ pkgs.email-mcp ];

    systemd.services.email-mcp = {
      description = "IMAP/SMTP email MCP gateway (with send approval gate)";
      # Proton Bridge is a systemd-USER service (owned by alex) — we cannot
      # order a system service after it across the user/system boundary. The
      # IMAP/SMTP clients instead retry-with-backoff on connect, so the service
      # comes up and /health degrades gracefully until Bridge answers.
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        EMAIL_MCP_BIND_IP = cfg.bindIp;
        EMAIL_MCP_PORT = toString cfg.port;
        EMAIL_MCP_TOKENS_FILE = config.sops.secrets.email_mcp_tokens.path;
        EMAIL_MCP_IMAP_ADDR = cfg.imapAddr;
        EMAIL_MCP_SMTP_ADDR = cfg.smtpAddr;
        EMAIL_MCP_DB = "/var/lib/email-mcp/pending.db";
      };

      serviceConfig = {
        ExecStart = "${pkgs.email-mcp}/bin/email-mcp";
        EnvironmentFile = config.sops.templates."email-mcp.env".path;
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/email-mcp" ];
      };
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
