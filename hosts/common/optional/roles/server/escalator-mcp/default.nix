{ lib, pkgs, config, ... }:
let
  cfg = config.escalator-mcp;
in
{
  options.escalator-mcp = {
    enable = lib.mkEnableOption "Escalator MCP — one-shot frontier-model consult via OpenRouter";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4285;
      description = "TCP port the escalator-mcp gateway listens on. Tailnet IP only.";
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
      default = "escalator_mcp";
      description = "System user to run the service as.";
    };

    expertModel = lib.mkOption {
      type = lib.types.str;
      default = "anthropic/claude-opus-4.7-fast";
      description = ''
        OpenRouter model slug for the consult_expert tool. Default is
        Claude Opus 4.7 Fast — the frontier escalation tier in this
        homelab. Must be on alex's OR account model allow-list.
      '';
    };

    maxOutputTokens = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = ''
        Hard cap on completion tokens per consult. Bounds spend on a
        single call: at Opus 4.7-fast's $150/Mtok output, 4096 tokens =
        ~$0.61 worst case per question.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.${cfg.user} = {
      isSystemUser = true;
      group = cfg.user;
      # Secondary membership in `hermes` lets this user read the shared
      # openrouter_api_key sops secret (mode 0440, group=hermes) that
      # hermes-agent declares. We share the same OR sub-key since this
      # work bills against the Hermes traffic budget anyway.
      extraGroups = [ "hermes" ];
      home = "/var/lib/escalator-mcp";
      createHome = true;
      description = "escalator-mcp service user";
    };
    users.groups.${cfg.user} = { };

    # Bearer tokens the MCP accepts from clients (Hermes). Same shape as
    # the other MCPs in this repo: JSON `{"tokens": {"client_name":
    # "hex-token"}}`. Currently the only client is hermes.
    sops.secrets.escalator_mcp_tokens = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      restartUnits = [ "escalator-mcp.service" ];
    };
    # openrouter_api_key is declared in hermes-agent's module (single
    # source of truth); we only reference its path below.

    sops.templates."escalator-mcp.env" = {
      owner = cfg.user;
      group = cfg.user;
      mode = "0400";
      restartUnits = [ "escalator-mcp.service" ];
      content = ''
        OPENROUTER_API_KEY=${config.sops.placeholder.openrouter_api_key}
      '';
    };

    environment.persistence."/persist".directories = [
      { directory = "/var/lib/escalator-mcp"; user = cfg.user; group = cfg.user; mode = "0750"; }
    ];
    systemd.tmpfiles.rules = [
      "d /var/lib/escalator-mcp 0750 ${cfg.user} ${cfg.user} -"
    ];

    environment.systemPackages = [ pkgs.escalator-mcp ];

    systemd.services.escalator-mcp = {
      description = "Escalator MCP — one-shot frontier-model consult";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        ESCALATOR_MCP_BIND_IP = cfg.bindIp;
        ESCALATOR_MCP_PORT = toString cfg.port;
        ESCALATOR_MCP_TOKENS_FILE = config.sops.secrets.escalator_mcp_tokens.path;
        ESCALATOR_MCP_EXPERT_MODEL = cfg.expertModel;
        ESCALATOR_MCP_MAX_OUTPUT_TOKENS = toString cfg.maxOutputTokens;
      };

      serviceConfig = {
        ExecStart = "${pkgs.escalator-mcp}/bin/escalator-mcp";
        EnvironmentFile = config.sops.templates."escalator-mcp.env".path;
        User = cfg.user;
        Group = cfg.user;
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = true;
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ "/var/lib/escalator-mcp" ];
      };
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
