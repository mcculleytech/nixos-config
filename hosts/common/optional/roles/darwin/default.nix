{ lib, config, outputs, ... }:
{
  imports = [
    ./claude-code-telemetry.nix
    ../../../global/homelab-domain.nix
  ];

  config = {
    nix.settings = {
      experimental-features = [ "nix-command" "flakes" ];
      trusted-users = [ "root" "@admin" "alex" ];
      extra-substituters = [
        "https://nix-community.cachix.org"
        "https://claude-code.cachix.org"
      ];
      extra-trusted-public-keys = [
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      ];
    };

    nixpkgs = {
      overlays = [
        outputs.overlays.additions
        outputs.overlays.unstable-packages
        # direnv 2.37.1's `make test-fish` gets SIGKILLed in the build sandbox on
        # Apple Silicon. Skip the test suite — direnv itself works fine.
        (final: prev: {
          direnv = prev.direnv.overrideAttrs (_: { doCheck = false; });
        })
      ];
      config.allowUnfree = true;
    };

    programs.zsh.enable = true;

    # nix-darwin counterpart to the NixOS `os-rebuild` alias in
    # hosts/common/global/env-vars.nix. Home-manager is wired in as a
    # darwin module (see flake.nix), so one switch covers system + home.
    environment.shellAliases = {
      mac-rebuild = "sudo darwin-rebuild switch --flake '/Users/alex/Repositories/personal/nixos-config/#'$(hostname -s)";
    };

    # cmux (0.64.19) bundles its own Ghostty shell integration, which
    # defines a `ssh` shell function that re-execs through
    # `$GHOSTTY_BIN_DIR/ghostty +ssh`. cmux's spawned process env sets
    # GHOSTTY_BIN_DIR=/Applications/cmux.app/Contents/MacOS, but that
    # bundle actually ships the ghostty binary under
    # Contents/Resources/bin/ghostty — so every `ssh` in a cmux shell
    # fails with "no such file or directory". Override it here: like the
    # telemetry vars in claude-code-telemetry.nix, environment.variables
    # lands in /etc/zshenv, which zsh sources before cmux points ZDOTDIR
    # at its own integration scripts, so this sticks for the rest of
    # shell startup.
    environment.variables = {
      GHOSTTY_BIN_DIR = "/Applications/cmux.app/Contents/Resources/bin";
    };

    # Phase 1 of the Mac/Nix decouple (see README): these all moved to
    # homebrew, declared in hosts/faramir/configuration.nix. git, git-crypt,
    # sops, age and ripgrep were already installed via brew before the move
    # (verified with `brew list --formula`), so nothing needed bootstrapping;
    # curl/jq/fd/bat were added to the brews list at the same time.
    #
    # The secrets toolchain (sops + age + git-crypt) is what lets alex@faramir
    # edit sops files and unlock this repo's git-crypt symmetric key — age is
    # sops' encryption backend, needed for `age-keygen` if a fresh key is ever
    # required. Keep all three declared in brew for as long as faramir edits
    # secrets, regardless of how far the decouple goes.
    environment.systemPackages = [ ];

    homebrew = {
      enable = true;
      onActivation = {
        autoUpdate = true;
        upgrade = true;
        # `cleanup = "zap"` will uninstall+wipe ANY brew/cask/tap not
        # declared here. That's destructive on a system where Homebrew is
        # also used imperatively — a single forgotten declaration wipes
        # the app and its data. Use "none" to make the homebrew block
        # additive ("ensure these are present") and only flip back to
        # "uninstall" or "zap" if/when faramir's homebrew is fully
        # declarative. See 2026-05-20 incident: zap removed 48 casks +
        # 190 formulae before being blocked by a dependency.
        cleanup = "none";
      };
      taps = [ ];
      brews = [ ];
      casks = [ ];
    };

    users.users.alex = {
      home = "/Users/alex";
    };

    system.primaryUser = "alex";
    system.stateVersion = 6;
  };
}
