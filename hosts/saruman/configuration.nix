{ inputs, config, pkgs, lib,  ... }: {
  imports =
    [
      ./hardware-configuration.nix
      ../common/global
      ../common/optional
      ../common/optional/roles/server
      ../common/optional/roles/server/hermes-agent  # saruman-only — depends on
                                                    # upstream services.hermes-agent
                                                    # option from the flake input
      ../common/optional/roles/server/hermes-dashboard  # saruman-only — pulls
                                                        # the upstream hermes-agent
                                                        # package out of the input
      ../common/optional/roles/workstation
      ../../disko/saruman.nix
    ];

  # module enable
  docker.enable = true;
  nvidia.enable = true;
  opengl.enable = true;
  jellyfin.enable = true;
  octoprint.enable = true;
  ollama.enable = true;
  steam.enable = true;
  immich.enable = true;
  open-webui.enable = true;
  n8n.enable = true;
  paperless.enable = true;
  kde.enable = true;
  bluetooth.enable = true;
  kokoro.enable = true;
  speaches.enable = true;  # GPU-accelerated Whisper STT (OpenAI-compatible) on tailnet :8000
  lab.protonmail-bridge.enable = true;  # headless Bridge for hermes email integration
  auto-deploy.enable = true;
  tailscale-server.enable = true;
  agent-memory.enable = true;
  lab.nas-backups.enable = true;  # NFS-mounted /mnt/nas-backups for off-host backups
  obsidian-backup.enable = true;   # daily rsync of /home/alex/obsidian → NAS
  obsidian-headless.enable = true;
  vault-mcp.enable = true;
  hermes-agent.enable = true;  # transitively enables signal-cli
  signal-mcp.enable = true;    # outbound Signal MCP with approval gate
  radicale-mcp.enable = true;  # CalDAV/CardDAV MCP (talks to phantom's Radicale)
  miniflux-mcp.enable = true;  # Miniflux RSS reader MCP (talks to phantom's Miniflux)
  gcal-mcp.enable = true;      # Google Calendar MCP (reuses hermes's google-workspace OAuth)
  escalator-mcp.enable = true; # one-shot consult_expert tool (Anthropic Opus via OR)
  prometheus-mcp.enable = true; # read-only Prometheus + Alertmanager queries (talks to atreides:9090)
  email-mcp.enable = true;     # IMAP/SMTP via Proton Bridge (read + approval-gated send)
  hermes-dashboard.enable = true;  # web UI behind traefik (auth + tailnet allowlist)
  vault-indexer.enable = true;  # hourly: chunk vault → embed → agent_memory


  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.interfaces.enp5s0.wakeOnLan.enable = true;

  environment.systemPackages = with pkgs; [
    unstable.nvidia-docker
    unstable.flameshot
    unstable.zrok
  ];

  # virtualisation.docker = {
  #   enableNvidia = true;
  # };

  networking.hostName = "saruman";
  networking.networkmanager.enable = true;

  # ─── Podman storage on the big disk ───────────────────────────────────────
  # Relocate podman's graphroot to encryptedHome (/home, 932GB) instead of
  # encryptedRoot (the 233GB NVMe shared with /nix). Without this, container
  # image weight (Kokoro 13.7GB + whatever else) competes with the Nix store
  # for the small disk — caused the 2026-05-26 disk-full cascade where a
  # deploy storm couldn't recover even with manual GC.
  #
  # /home is on a separate LUKS+btrfs disk, not subject to impermanence, so
  # the new graphroot persists across reboots naturally — no /persist binds
  # needed. runroot stays in /run (tmpfs) per upstream default; it's
  # ephemeral runtime state and small.
  #
  # Migration: stop podman-*.service, rsync /var/lib/containers/storage/ to
  # /home/podman/storage/, deploy, services restart reading new path.
  virtualisation.containers.storage.settings.storage = {
    driver = "overlay";
    graphroot = "/home/podman/storage";
    runroot = "/run/containers/storage";
  };
  systemd.tmpfiles.rules = [
    "d /home/podman 0700 root root -"
    "d /home/podman/storage 0700 root root -"
  ];

  time.timeZone = "America/Chicago";

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    # alsa.support32Bit = true; # disabled — pulls i686 nodejs via npm-config-hook causing build stalls
    pulse.enable = true;
  };

  programs.dconf.enable = true;

 # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  system.stateVersion = "24.05";

}
