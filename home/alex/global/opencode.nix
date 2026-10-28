{ lib, pkgs, osConfig, ... }:
let
  homelabDomain = osConfig.lab.homelabDomain;

  # Contexts match OLLAMA_CONTEXT_LENGTH (32k) set server-side in
  # hosts/common/optional/roles/server/ollama.nix.
  sarumanOllama = {
    npm = "@ai-sdk/openai-compatible";
    name = "Saruman Ollama (homelab)";
    options = {
      baseURL = "https://ollama.${homelabDomain}/v1";
      apiKey = "dummy";
    };
    models = {
      # Picked by the 2026-10-28 tool-call eval (27/27 on both).
      "ornith-1.5:9b" = {
        name = "Ornith 1.5 9B (tool use, fastest)";
        limit = { context = 32768; output = 8192; };
        tools = true;
        reasoning = true;
      };
      "gemma4:12b-it-qat" = {
        name = "Gemma 4 12B QAT (general chat)";
        limit = { context = 32768; output = 8192; };
        tools = true;
        reasoning = true;
      };
      "qwen3-coder:30b" = {
        name = "Qwen3 Coder 30B (MoE, partial CPU offload)";
        limit = { context = 32768; output = 8192; };
        tools = true;
        reasoning = false;
      };
      "gemma4:12b" = {
        name = "Gemma 4 12B";
        limit = { context = 32768; output = 8192; };
        tools = true;
        reasoning = false;
      };
      "huihui_ai/gemma-4-abliterated:12b" = {
        name = "Gemma 4 12B Abliterated (huihui, vision)";
        limit = { context = 32768; output = 8192; };
        tools = true;
        reasoning = false;
      };
      "gemma4:latest" = {
        name = "Gemma 4 8B";
      };
    };
  };

in
{
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    theme = "nord";
    plugin = [ "@slkiser/opencode-quota" ];
    provider = { saruman-ollama = sarumanOllama; };
  };
}
