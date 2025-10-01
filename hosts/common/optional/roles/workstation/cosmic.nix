{ lib, pkgs, inputs, config, ... }:

let
  unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config = pkgs.config;
  };
in
{
  options.services.desktopManager.cosmic.useUnstable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Use Cosmic packages and module from nixpkgs-unstable.";
  };

  config = lib.mkIf config.services.desktopManager.cosmic.useUnstable {
    disabledModules = [
      "services/desktop-managers/cosmic.nix"
    ];

    imports = [
      "${inputs.nixpkgs-unstable}/nixos/modules/services/desktop-managers/cosmic.nix"
    ];

    nixpkgs.overlays = [
      (final: prev: {
        cosmic = unstable.cosmic;
      })
    ];

    # you can also put extra environment.systemPackages here if needed
  };

  services.desktopManager.cosmic.enable = true;
  services.desktopManager.cosmic.useUnstable = true;
}
