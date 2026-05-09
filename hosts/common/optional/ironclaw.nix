{ lib, ... }:
{
  options.lab.ironclaw = {
    enable = lib.mkEnableOption "ironclaw agent OS";
    fromBrew = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Install via Homebrew (`brew install ironclaw`) instead of the Nix
        derivation. Useful on Darwin while the Nix build is maturing; has no
        effect on Linux.
      '';
    };
  };

  options.lab.signalChannel = {
    enable = lib.mkEnableOption "ironclaw Signal channel via signal-cli HTTP daemon";
    httpPort = lib.mkOption {
      type = lib.types.port;
      default = 8088;
      description = ''
        Local port the signal-cli HTTP daemon listens on. Default 8088 because
        bloodhound owns 8080 on this box.
      '';
    };
  };
}
