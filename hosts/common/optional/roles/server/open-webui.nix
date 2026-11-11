{ pkgs, lib, config, ... }:

{
  options = {
    open-webui.enable =
      lib.mkEnableOption "enables open-webui for ollama";
  };

  config = lib.mkIf config.open-webui.enable {
    users.users.open-webui = {
      isSystemUser = true;
      group = "open-webui";
    };
    users.groups.open-webui = {};

    services.open-webui = {
      enable = true;
      host = "0.0.0.0";
      openFirewall = true;
      stateDir = "/var/lib/open-webui";
    };

    systemd.services.open-webui.serviceConfig = {
      DynamicUser = lib.mkForce false;
      PrivateUsers = lib.mkForce false;
      User = "open-webui";
      Group = "open-webui";
      # Carries the OpenRouter key; rendered by sops-nix at activation.
      EnvironmentFile = [ config.sops.templates."open-webui.env".path ];
    };

    systemd.tmpfiles.rules = [
      "d /var/lib/open-webui 0750 open-webui open-webui -"
    ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/open-webui"; user = "open-webui"; group = "open-webui"; }
        ];
      };
    };

    # ---------------------------------------------------------------------
    # Inference + audio wiring
    # ---------------------------------------------------------------------

    sops.secrets.openrouter_api_key = {};

    # OPENAI_API_KEYS is split on ';' (a bare key list) when read from the
    # environment, unlike the DB column which stores a JSON array — so a single
    # key needs no quoting here.
    sops.templates."open-webui.env" = {
      owner = "open-webui";
      group = "open-webui";
      mode = "0400";
      content = ''
        OPENAI_API_KEYS=${config.sops.placeholder.openrouter_api_key}
      '';
    };

    # These are DEFAULTS, not overrides. open-webui persists each of these keys
    # in its own DB (the `config` table) and, with ENABLE_PERSISTENT_CONFIG
    # defaulting to True, the stored value wins over the environment. They make
    # a fresh /var/lib/open-webui come up correct; to re-seed an existing
    # install, delete that key's row from `config` and restart the unit.
    systemd.services.open-webui.environment = {
      # Chat inference: OpenRouter, plus the local ollama.
      ENABLE_OPENAI_API = "true";
      OPENAI_API_BASE_URLS = "https://openrouter.ai/api/v1";
      ENABLE_OLLAMA_API = "true";
      OLLAMA_BASE_URLS = "http://127.0.0.1:11434";

      # Dictation -> speaches (faster-whisper-large-v3-turbo, saruman:8000).
      # This is the stt.* host, not tts.*: kokoro serves no
      # /v1/audio/transcriptions and answers 404 there.
      AUDIO_STT_ENGINE = "openai";
      AUDIO_STT_OPENAI_API_BASE_URL = "https://stt.${config.lab.homelabDomain}/v1";
      AUDIO_STT_OPENAI_API_KEY = "dummy"; # speaches does not authenticate
      AUDIO_STT_MODEL = "deepdml/faster-whisper-large-v3-turbo-ct2";

      # Read-aloud -> kokoro (saruman:8880).
      AUDIO_TTS_ENGINE = "openai";
      AUDIO_TTS_OPENAI_API_BASE_URL = "https://tts.${config.lab.homelabDomain}/v1";
      AUDIO_TTS_OPENAI_API_KEY = "local";
      AUDIO_TTS_MODEL = "kokoro";
      AUDIO_TTS_VOICE = "af_alloy";
    };
  };
}
