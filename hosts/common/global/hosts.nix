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
        # Optional — only set for hosts that bind tailnet-only services and
        # need to be reached over the tailnet from other hosts. Backfill as
        # services start needing it; not every host has one.
        tailnetIp = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
        };
      };
    });
    default = {};
    description = "Centralized host inventory for the homelab.";
  };

  config.lab.hosts = hostData;
}
