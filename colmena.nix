# Thin mapping layer — host definitions live in flake.nix's hostDefs.
# This file only adds colmena's deployment metadata and meta block.
{ inputs, outputs, hostDefs }:
{
  meta = {
    nixpkgs = import inputs.nixpkgs { localSystem = "x86_64-linux"; };
    specialArgs = { inherit inputs outputs; };
  };
} // builtins.mapAttrs (_name: def: {
  deployment = def.deployment;
  imports = def.modules;
}) hostDefs
