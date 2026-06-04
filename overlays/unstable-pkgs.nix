# This file defines overlays
{ inputs, ... }:
let
  # Version string stamped into every locally-built package. Derived from the
  # repo's flake metadata at evaluation time — no impure git calls, no
  # committed VERSION files.
  #
  # Shape: 0.1.0+YYYY.MM.DD.<short-sha>[.dirty]
  #   * Public segment "0.1.0" — placeholder; bump manually for milestones
  #   * Local segment after "+" — dotted-segment date + commit + optional
  #     dirty marker. PEP 440 requires `.` as separator (NOT `-`) and bans
  #     leading zeros in the public segment, hence keeping the date in the
  #     local label rather than the main version.
  #   * "dirty" appears when deploying with uncommitted working-tree changes
  #     (Nix flakes expose self.dirtyShortRev only in that case).
  selfVersion = let
    date = builtins.substring 0 8 (inputs.self.lastModifiedDate or "00000000");
    iso = "${builtins.substring 0 4 date}.${builtins.substring 4 2 date}.${builtins.substring 6 2 date}";
    # self.shortRev is set only on clean trees; self.dirtyShortRev (e.g.
    # "abc1234-dirty") is set only on dirty trees. PEP 440 local segments
    # forbid hyphens, so we normalize "-" → "." to convert "abc1234-dirty"
    # into "abc1234.dirty" — which carries the same information in a
    # spec-compliant form.
    rawRev = inputs.self.shortRev or inputs.self.dirtyShortRev or "unknown";
    rev = builtins.replaceStrings [ "-" ] [ "." ] rawRev;
  in "0.1.0+${iso}.${rev}";
in
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; version = selfVersion; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      localSystem = final.stdenv.hostPlatform.system;
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "openssl-1.1.1w"
          "electron-25.9.0"
          "electron-39.8.10" # unstable obsidian/signal/bitwarden/beeper bundle this
        ];
      };
      overlays = [];
    };
  };


}
