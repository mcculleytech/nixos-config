{ lib, pkgs, inputs, config, ... }:

let
  # Import unstable pkgs for this system
  unstable = import inputs.nixpkgs-unstable {
    system = pkgs.system;
    config = pkgs.config;
  };
in
{
  ##############################
  # Module options
  ##############################
  options.services.desktopManager.cosmic.useUnstable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Use Cosmic packages and module from nixpkgs-unstable.";
  };

  options.services.displayManager.cosmicGreeter.useUnstable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = "Use Cosmic greeter from nixpkgs-unstable.";
  };

  ##############################
  # Conditional config overrides
  ##############################
  config = lib.mkIf config.services.desktopManager.cosmic.useUnstable {
    disabledModules = [
      "services/desktop-managers/cosmic.nix"
    ];

    imports = [
      "${inputs.nixpkgs-unstable}/nixos/modules/services/desktop-managers/cosmic.nix"
    ];

    nixpkgs.overlays = [
      (final: prev: {
        # Expose unstable Cosmic packages so module uses them
        cosmic = unstable.cosmic;
      })
    ];
  };

  # Optional: Greeter override
  config = lib.mkIf config.services.displayManager.cosmicGreeter.useUnstable {
    disabledModules = [
      "services/desktop-managers/cosmic-greeter.nix"
    ];

    imports = [
      "${inputs.nixpkgs-unstable}/nixos/modules/services/desktop-managers/cosmic-greeter.nix"
    ];

    nixpkgs.overlays = [
      (final: prev: {
        cosmic-greeter = unstable.cosmic-greeter;
      })
    ];
  };
}
