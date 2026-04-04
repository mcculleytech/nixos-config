{ lib, ... }:
let
  hostData = import ../hosts-data.nix;
in
{
  options.lab.hosts = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        ip = lib.mkOption { type = lib.types.str; };
        role = lib.mkOption {
          type = lib.types.enum [ "server" "workstation" "infrastructure" ];
        };
      };
    });
    default = {};
    description = "Centralized host inventory for the homelab.";
  };

  config.lab.hosts = hostData;
}
