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
        "/home/ollama/whisper-models:/home/ubuntu/.cache/huggingface"
      ];
      environment = {
        WHISPER__MODEL = "Systran/faster-whisper-large-v3-turbo";
        WHISPER__COMPUTE_TYPE = "float16";
      };
      extraOptions = [ "--device" "nvidia.com/gpu=all" ];
    };

    systemd.tmpfiles.rules = [
      "d /home/ollama/whisper-models 0755 ollama ollama -"
    ];

    # Tailnet-only — saruman.tailnet:8000. Trust boundary is the tailnet,
    # matching how Ollama on this host is exposed. No bearer auth.
    networking.firewall.interfaces.tailscale0.allowedTCPPorts = [ 8000 ];
  };
}
