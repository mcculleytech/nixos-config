{ ... }:
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
    ./escalator
    ./miniflux
  ];
}
