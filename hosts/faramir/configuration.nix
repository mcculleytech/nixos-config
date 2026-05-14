{ lib, pkgs, ... }:
{
  imports = [
    ../common/optional/roles/darwin
  ];

  networking.hostName = "faramir";
  networking.computerName = "faramir";

  lab.lmStudio.autoStart = true;
  lab.lmStudio.autoLoadModel = "qwen/qwen3.6-27b";

  homebrew.casks = [
    "lm-studio"
    "wispr-flow"
  ];

  time.timeZone = "America/Chicago";
}
