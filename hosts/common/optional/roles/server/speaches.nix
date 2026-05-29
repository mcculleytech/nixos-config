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

    systemd.tmpfiles.rules = [
      "d /home/ollama/whisper-models 0755 ollama ollama -"
      # Pre-create the huggingface_hub cache subdir — speaches calls
      # huggingface_hub.scan_cache_dir() at startup which errors hard
      # (CacheNotFound) if /home/ubuntu/.cache/huggingface/hub doesn't
      # exist inside the container. The `:U` mount option chowns both
      # parent and child to the container user.
      "d /home/ollama/whisper-models/hub 0755 ollama ollama -"
    ];

    # Open :8000 on all interfaces — same posture as Kokoro and Ollama
    # on this host. Reverse-proxied by Traefik on atreides at
    # https://stt.${homelab_domain}; tailnet + LAN can both reach it
    # directly or via the proxy. No bearer auth.
    networking.firewall.allowedTCPPorts = [ 8000 ];
  };
}
