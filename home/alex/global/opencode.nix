{ lib, pkgs, osConfig, ... }:
let
  homelabDomain = osConfig.lab.homelabDomain;

  sarumanOllama = {
    npm = "@ai-sdk/openai-compatible";
    name = "Saruman Ollama (homelab)";
    options = {
      baseURL = "https://ollama.${homelabDomain}/v1";
      apiKey = "dummy";
    };
    models = {
      "qwen3:4b-instruct-28k" = {
        name = "Qwen3 4B Instruct (28k ctx, tool use, no thinking)";
        limit = { context = 28672; output = 4096; };
        tools = true;
        reasoning = false;
      };
      "qwen3:14b-16k" = {
        name = "Qwen3 14B (16k ctx, chat)";
        limit = { context = 16384; output = 4096; };
        tools = true;
        reasoning = false;
      };
      "phi4:14b-16k" = {
        name = "Phi-4 14B (16k ctx, chat/reasoning)";
        limit = { context = 16384; output = 4096; };
        tools = false;
        reasoning = false;
      };
      "gemma4:12b" = {
        name = "Gemma 4 12B (4k ctx — Ollama default, not bumped)";
        limit = { context = 4096; output = 8192; };
        tools = true;
        reasoning = false;
      };
      "huihui_ai/gemma-4-abliterated:12b" = {
        name = "Gemma 4 12B Abliterated (huihui, vision)";
        limit = { context = 4096; output = 8192; };
        tools = true;
        reasoning = false;
      };
      "gemma4:latest" = {
        name = "Gemma 4 8B";
      };
    };
  };

  lmStudio = lib.optionalAttrs pkgs.stdenv.isDarwin {
    lmstudio = {
      npm = "@ai-sdk/openai-compatible";
      name = "LM Studio (local)";
      options.baseURL = "http://127.0.0.1:1234/v1";
      models = {
        "qwen3-coder-30b-a3b-instruct-mlx".name = "Qwen3 Coder 30B A3B (MLX)";
        "gemma-4-31b-it-mlx".name = "Gemma 4 31B IT (MLX)";
        "gemma-4-26b-a4b-it".name = "Gemma 4 26B A4B IT";
        "supergemma4-26b-abliterated-multimodal-mlx".name =
          "SuperGemma4 26B Abliterated Multimodal (MLX)";
        "gemma-4-26b-a4b-it-uncensored-abliterix-mlx-int2-affine".name =
          "Gemma 4 26B A4B IT Uncensored Abliterix (MLX int2)";
      };
    };
  };
in
{
  xdg.configFile."opencode/opencode.json".text = builtins.toJSON {
    "$schema" = "https://opencode.ai/config.json";
    provider = { saruman-ollama = sarumanOllama; } // lmStudio;
  };
}
