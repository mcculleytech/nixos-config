{ pkgs, config, lib, ... }: {

  options.openwhispr.enable =
    lib.mkEnableOption "OpenWhispr dictation client (Electron AppImage wrap)";

  config = lib.mkIf config.openwhispr.enable {
    # `pkgs.openwhispr` is exposed via the repo's pkgs overlay
    # (pkgs/default.nix → pkgs/openwhispr/default.nix), which wraps the
    # upstream AppImage with appimageTools. Source-building this app from
    # scratch would require ~100h of work (whisper-cpp + llama-server +
    # sherpa-onnx + qdrant + diarization models + electron-builder).
    home.packages = [ pkgs.openwhispr ];

    # OpenWhispr client gotchas (also documented in
    # hosts/common/optional/roles/server/speaches.nix):
    #
    # 1. Use the "Self-hosted server" toggle URL field, NOT the "Custom"
    #    provider field — the self-hosted branch silently overrides
    #    Custom, and Custom-alone leaks requests to api.openai.com.
    # 2. OpenWhispr ≤1.7.0 ignored the self-hosted URL entirely
    #    (upstream issue #750, fixed in 1.7.1). Pin ≥1.7.2.
    # 3. STT model field is hardcoded to "whisper-1"; speaches maps that
    #    to Systran/faster-whisper-large-v3, which must be pre-pulled
    #    on saruman.
    #
    # Recommended endpoint config:
    #   STT URL     = https://stt.<homelab-domain>/v1
    #   Cleanup URL = https://ollama.<homelab-domain>/v1
    # (substitute config.lab.homelabDomain — see hosts/common/global/homelab-domain.nix)
    #   Cleanup model = gemma4:latest
    #   API keys    = blank (tailnet is the trust boundary)
  };
}
