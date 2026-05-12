{ pkgs }:
{
  ironclaw = pkgs.callPackage ./ironclaw { rustPlatform = pkgs.unstable.rustPlatform; };
  agent-memory-mcp = pkgs.callPackage ./agent-memory-mcp { python3 = pkgs.python3; };
  obsidian-headless = pkgs.callPackage ./obsidian-headless { };
  vault-mcp = pkgs.callPackage ./vault-mcp { python3 = pkgs.python3; };
  signal-mcp = pkgs.callPackage ./signal-mcp { python3 = pkgs.python3; };
  radicale-mcp = pkgs.callPackage ./radicale-mcp { python3 = pkgs.python3; };
  miniflux-mcp = pkgs.callPackage ./miniflux-mcp { python3 = pkgs.python3; };
}
