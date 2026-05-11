{ pkgs }:
{
  ironclaw = pkgs.callPackage ./ironclaw { rustPlatform = pkgs.unstable.rustPlatform; };
  agent-memory-mcp = pkgs.callPackage ./agent-memory-mcp { python3 = pkgs.python3; };
  obsidian-headless = pkgs.callPackage ./obsidian-headless { };
  vault-mcp = pkgs.callPackage ./vault-mcp { python3 = pkgs.python3; };
}
