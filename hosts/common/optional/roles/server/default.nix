{
  imports = [
    ./radicale.nix
    ./xonotic.nix
    ./octoprint.nix
    ./jellyfin.nix
    ./laptop-disable-suspend-on-close.nix
    ./ollama.nix
    ./immich.nix
    ./qemu-config.nix
    ./blocky.nix
    ./acme.nix
    ./homepage-dashboard.nix
    ./home-impermanence.nix
    ./gitea
    ./traefik
    ./tailscale-server.nix
    ./syncthing-server.nix
    ./open-webui.nix
    ./n8n.nix
    ./miniflux.nix
    ./paperless.nix
    ./prometheus.nix
    ./grafana.nix
    ./smokeping.nix
    ./ntfy.nix
    ./kokoro.nix
    ./auto-deploy.nix
    ./agent-memory
    ./obsidian-headless
    ./vault-mcp
    ./signal-cli
    # ./hermes-agent  — imported on saruman only (hosts/saruman/configuration.nix)
    # because it sets services.hermes-agent.* which only exists where the
    # upstream NousResearch/hermes-agent NixOS module is loaded.
  ];
}
