{ pkgs }:
{
  ironclaw = pkgs.callPackage ./ironclaw { rustPlatform = pkgs.unstable.rustPlatform; };
  agent-memory-mcp = pkgs.callPackage ./agent-memory-mcp { python3 = pkgs.python3; };
}
