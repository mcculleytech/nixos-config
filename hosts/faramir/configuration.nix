{ lib, pkgs, ... }:
{
  imports = [
    ../common/optional/roles/darwin
  ];

  networking.hostName = "faramir";
  networking.computerName = "faramir";

  homebrew.brews = [
    # pgvector's homebrew bottle is built against pg@17/@18 (not @15), so we
    # use @18 for ironclaw's vector store. ironclaw requires Postgres 15+ —
    # @18 satisfies that. Runs on default port 5432.
    "postgresql@18"
    "pgvector"
  ];

  lab.signalChannel.enable = true;

  lab.lmStudio.autoStart = true;
  lab.lmStudio.autoLoadModel = "qwen/qwen3.6-27b";

  homebrew.casks = [
    "lm-studio"
  ];

  time.timeZone = "America/Chicago";
}
