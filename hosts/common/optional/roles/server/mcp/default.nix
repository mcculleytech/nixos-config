{ lib, pkgs, config, ... }:
let
  # Every MCP gateway binds to the host's tailnet IPv4, resolved at service
  # start via `tailscale ip -4`. `After=tailscaled.service` (set in each unit)
  # only orders process *spawn*, not readiness: on a deploy that restarts
  # tailscaled, the daemon goes "active" several seconds before it has
  # re-established the tunnel and reassigned the IP. Every MCP then loses that
  # race and exits 1 with `bind ip: tailscale ip -4: exit status 1`. systemd's
  # Restart= heals them within ~5s, but colmena snapshots the failure and the
  # deploy is reported failed (exit 4). Gate each MCP on tailscale readiness so
  # they come up clean on the first try. Defined centrally — rather than in
  # each module — so the rationale lives in one place; this merges with each
  # unit's own serviceConfig.
  waitTailnetIp = "${pkgs.wait-tailnet-ip}/bin/wait-tailnet-ip";
  tailnetMcpUnits = {
    agent-memory-mcp = config.agent-memory.enable;
    email-mcp        = config.email-mcp.enable;
    escalator-mcp    = config.escalator-mcp.enable;
    gcal-mcp         = config.gcal-mcp.enable;
    miniflux-mcp     = config.miniflux-mcp.enable;
    prometheus-mcp   = config.prometheus-mcp.enable;
    radicale-mcp     = config.radicale-mcp.enable;
    signal-mcp       = config.signal-mcp.enable;
    vault-mcp        = config.vault-mcp.enable;
  };
in
{
  # ─── MCP server modules ──────────────────────────────────────────────────
  # All NixOS modules that host an MCP service live under this directory.
  # Each MCP follows the standard shape: dedicated system user, sops bearer
  # tokens, tailnet-only firewall opening, systemd unit. The package source
  # lives at `pkgs/<name>-mcp/` and is wired in via `pkgs.<name>-mcp`.
  #
  # New MCPs are written in Go (see CLAUDE.md → MCP conventions). Add a new
  # one by: 1) creating `pkgs/<name>-mcp/{main.go,go.mod,go.sum,default.nix}`,
  # 2) registering in `pkgs/default.nix`, 3) creating `./<name>/default.nix`
  # here, 4) appending the import below, 5) enabling on the relevant host.
  imports = [
    ./agent-memory
    ./email
    ./escalator
    ./gcal
    ./miniflux
    ./prometheus
    ./radicale
    ./signal
    ./vault
  ];

  # Prepend the tailnet-readiness gate to every enabled MCP unit (see above).
  config.systemd.services = lib.mapAttrs
    (_unit: enabled: lib.mkIf enabled {
      serviceConfig.ExecStartPre = [ waitTailnetIp ];
    })
    tailnetMcpUnits;
}
