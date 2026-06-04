{ config, lib, ... }: {

  options = {
    speaches.enable =
      lib.mkEnableOption "enables speaches STT server (OpenAI-compatible Whisper, GPU-accelerated)";
  };

  config = lib.mkIf config.speaches.enable {

    # Speaches: podman container exposing OpenAI-compatible
    # /v1/audio/transcriptions on :8000. Whisper weights cached under
    # /home/ollama/whisper-models (encryptedHome volume, same disk as
    # Ollama models — survives impermanence). Default model preselects
    # large-v3-turbo (FP16) — Pascal-friendly, ~2 GB VRAM, ~4× faster
    # than large-v3 with minimal quality loss for dictation.
    virtualisation.oci-containers.containers.speaches = {
      image = "ghcr.io/speaches-ai/speaches:latest-cuda";
      ports = [ "8000:8000" ];
      volumes = [
        # `:U` tells podman to chown the host dir to match the container's
        # uid:gid on first start — speaches's image runs as `ubuntu`, not
        # `ollama`, so the bare bind-mount fails with EACCES otherwise.
        "/home/ollama/whisper-models:/home/ubuntu/.cache/huggingface:U"
      ];
      environment = {
        # Systran doesn't publish a turbo CT2 conversion — the community
        # standard is deepdml's. Speaches still loads on-demand via API,
        # so this only sets the default suggested model name.
        WHISPER__MODEL = "deepdml/faster-whisper-large-v3-turbo-ct2";
        # Pascal sm_61 has FP16 instructions but no tensor cores; CT2
        # rejects compute_type=float16 with "do not support efficient
        # float16 computation". int8_float32 keeps int8 weights with
        # float32 math — Pascal-safe, ~2 GB VRAM. Avoid int8_float16
        # and bf16 (both Volta+ only).
        WHISPER__COMPUTE_TYPE = "int8_float32";
      };
      extraOptions = [ "--device" "nvidia.com/gpu=all" ];
    };

    # Pre-create the cache dirs so speaches's startup scan_cache_dir() finds
    # /home/ubuntu/.cache/huggingface/hub (it errors hard with CacheNotFound
    # otherwise). Ownership is left to podman: the `:U` mount option chowns the
    # volume to the container's `ubuntu` uid at container start. The owner/group
    # fields MUST be "-" (leave unmodified on existing inodes) — pinning them to
    # `ollama` re-chowns the dir away from the container user on every
    # activation, and since the long-running container isn't restarted by a
    # `switch`, `:U` doesn't re-apply, so transcriptions then fail with EACCES
    # reading the cache (the container can't even traverse a 0700 ollama-owned
    # dir). Mode 0755 is harmless to re-assert; ownership is the part that bites.
    systemd.tmpfiles.rules = [
      "d /home/ollama/whisper-models 0755 - - -"
      "d /home/ollama/whisper-models/hub 0755 - - -"
    ];

    # Open :8000 on all interfaces — same posture as Kokoro and Ollama
    # on this host. Reverse-proxied by Traefik on atreides at
    # https://stt.${homelab_domain}; tailnet + LAN can both reach it
    # directly or via the proxy. No bearer auth.
    networking.firewall.allowedTCPPorts = [ 8000 ];

    # ─── OpenWhispr client gotcha ────────────────────────────────────────
    # When pointing OpenWhispr at this endpoint, set the URL under the
    # "Self-hosted server" toggle, NOT the separate "Custom" provider
    # field. Both store base URLs, but the Self-hosted branch silently
    # overrides Custom — configuring Custom alone results in requests
    # leaking to api.openai.com (debug logs show provider='custom',
    # rawBaseUrl=https://api.openai.com/v1). Also: OpenWhispr ≤1.7.0
    # had a separate bug ignoring the self-hosted URL entirely
    # (upstream issue #750, fixed in 1.7.1). Use ≥1.7.2.
    #
    # OpenWhispr's STT field is hardcoded to model="whisper-1" with no
    # dropdown; speaches maps that name to Systran/faster-whisper-large-v3,
    # so pull that model (not just the turbo) for OpenWhispr compatibility:
    #   sudo podman exec speaches huggingface-cli download \
    #     Systran/faster-whisper-large-v3
  };
}
