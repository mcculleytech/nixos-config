{ lib, pkgs, config, ... }:
let
  cfg = config.vault-mcp;
in
{
  options.vault-mcp = {
    enable = lib.mkEnableOption "vault MCP gateway (read/write/search over an Obsidian vault directory)";

    port = lib.mkOption {
      type = lib.types.port;
      default = 4281;
      description = "TCP port the vault MCP gateway listens on (tailnet IP only).";
    };

    bindIp = lib.mkOption {
      type = lib.types.str;
      default = "auto";
      description = ''
        IPv4 to bind. "auto" resolves the host's tailnet IP via
        `tailscale ip -4` at service start.
      '';
    };

    tailnetInterface = lib.mkOption {
      type = lib.types.str;
      default = "tailscale0";
      description = "Interface on which to open the MCP port in the firewall.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "alex";
      description = ''
        User to run vault-mcp as. Must have read+write access to the vault
        directory. On saruman this is `alex`, the same user that owns the
        vault and runs obsidian-headless.
      '';
    };

    vaultRoot = lib.mkOption {
      type = lib.types.path;
      default = "/home/alex/obsidian/Barrow-Downs";
      description = "Absolute path to the on-disk vault directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    sops.secrets.vault_mcp_tokens = {
      owner = cfg.user;
      group = "users";
      mode = "0400";
      restartUnits = [ "vault-mcp.service" ];
    };

    # `vault-mcp --version` on PATH for operator convenience.
    environment.systemPackages = [ pkgs.vault-mcp ];

    systemd.services.vault-mcp = {
      description = "Vault MCP gateway (Obsidian vault on disk)";
      after = [ "network-online.target" "tailscaled.service" ];
      wants = [ "network-online.target" "tailscaled.service" ];
      wantedBy = [ "multi-user.target" ];

      path = [ config.services.tailscale.package ];

      environment = {
        VAULT_MCP_BIND_IP = cfg.bindIp;
        VAULT_MCP_PORT = toString cfg.port;
        VAULT_MCP_ROOT = builtins.toString cfg.vaultRoot;
        VAULT_MCP_TOKENS_FILE = config.sops.secrets.vault_mcp_tokens.path;
      };

      serviceConfig = {
        ExecStart = "${pkgs.vault-mcp}/bin/vault-mcp";
        User = cfg.user;
        Group = "users";
        Restart = "on-failure";
        RestartSec = "5s";

        ProtectSystem = "strict";
        ProtectHome = false;  # vault lives under /home
        PrivateTmp = true;
        NoNewPrivileges = true;
        ReadWritePaths = [ cfg.vaultRoot ];
      };
    };

    networking.firewall.interfaces.${cfg.tailnetInterface}.allowedTCPPorts = [ cfg.port ];
  };
}
