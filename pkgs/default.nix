{ pkgs, version ? "0.0.0-dev" }:
{
  ironclaw = pkgs.callPackage ./ironclaw { rustPlatform = pkgs.unstable.rustPlatform; };
  agent-memory-mcp = pkgs.callPackage ./agent-memory-mcp { inherit version; };
  obsidian-headless = pkgs.callPackage ./obsidian-headless { };
  vault-mcp = pkgs.callPackage ./vault-mcp { inherit version; };
  signal-mcp = pkgs.callPackage ./signal-mcp { inherit version; };
  radicale-mcp = pkgs.callPackage ./radicale-mcp { inherit version; };
  miniflux-mcp = pkgs.callPackage ./miniflux-mcp { inherit version; };
  gcal-mcp = pkgs.callPackage ./gcal-mcp { inherit version; };
  email-mcp = pkgs.callPackage ./email-mcp { inherit version; };
  vault-indexer = pkgs.callPackage ./vault-indexer { python3 = pkgs.python3; inherit version; };
  escalator-mcp = pkgs.callPackage ./escalator-mcp { inherit version; };
  prometheus-mcp = pkgs.callPackage ./prometheus-mcp { inherit version; };
  hermes-plugin-common = pkgs.callPackage ./hermes-plugin-common { };
  hermes-plugin-intel = pkgs.callPackage ./hermes-plugin-intel {
    hermes-plugin-common = pkgs.callPackage ./hermes-plugin-common { };
  };
  hermes-plugin-today = pkgs.callPackage ./hermes-plugin-today {
    hermes-plugin-common = pkgs.callPackage ./hermes-plugin-common { };
  };
  hermes-plugin-spend = pkgs.callPackage ./hermes-plugin-spend { };
  hermes-skill-obsidian = pkgs.callPackage ./hermes-skill-obsidian { };
  antigravity-cli = pkgs.callPackage ./antigravity-cli { };
}
