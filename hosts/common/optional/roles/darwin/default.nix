{ lib, config, pkgs, outputs, ... }:
{
  imports = [
    ./claude-code-telemetry.nix
    ../../../global/homelab-domain.nix
  ];

  options.lab.lmStudio = {
    autoStart = lib.mkEnableOption "auto-start LM Studio local server at login (and optionally pre-load a model)";
    autoLoadModel = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "qwen/qwen3.6-27b";
      description = ''
        Optional LM Studio model identifier to load after starting the server.
        Set to null to start the server without loading any model. Note: LM
        Studio must have been launched once via the GUI to authorize headless
        operation; `lms` is a closed-source CLI shipped with the app.
      '';
    };
    serveHost = lib.mkOption {
      type = lib.types.str;
      default = "127.0.0.1";
      example = "100.90.82.127";
      description = ''
        Bind address for LM Studio's API server (`lms server start --host`).
        Defaults to loopback. Set to this Mac's *tailnet* IP to expose the
        endpoint to the tailnet (e.g. so Hermes on saruman can reach it) —
        NOT 0.0.0.0, since this is a roaming laptop and 0.0.0.0 would expose
        the unauthenticated API on whatever (possibly untrusted) network it's
        joined to. When non-loopback, `--cors` is also enabled. Requires
        LM Studio ≥0.4 for the `--host` flag.
      '';
    };
  };

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

    environment.systemPackages = with pkgs; [
      curl
      git
      jq
      ripgrep
      fd
      bat
      # Secrets toolchain — lets alex@faramir edit sops files and unlock the
      # git-crypt symmetric key on this repo. age is sops' encryption backend
      # and is needed for `age-keygen` if a fresh key is ever required.
      sops
      age
      git-crypt
    ];

    launchd.user.agents = lib.optionalAttrs config.lab.lmStudio.autoStart {
      lms-server = {
        # `lms server start` brings up LM Studio's local API (default
        # 127.0.0.1:1234) and exits immediately. If autoLoadModel is set, queue
        # a model load so the LLM endpoint is warmed up before first request.
        # When serveHost is non-loopback, bind there + enable CORS so tailnet
        # clients (e.g. Hermes on saruman) can reach it.
        # KeepAlive disabled — the command is one-shot, not a long-running daemon.
        command =
          let
            lms = "/Users/alex/.lmstudio/bin/lms";
            hostArg = lib.optionalString (config.lab.lmStudio.serveHost != "127.0.0.1")
              " --host ${config.lab.lmStudio.serveHost} --cors";
            loadCmd = lib.optionalString (config.lab.lmStudio.autoLoadModel != null)
              " && ${lms} load '${config.lab.lmStudio.autoLoadModel}'";
          in
          "/bin/sh -c '${lms} server start${hostArg}${loadCmd}'";
        serviceConfig = {
          RunAtLoad = true;
          KeepAlive = false;
          StandardOutPath = "/Users/alex/Library/Logs/lms-server.out.log";
          StandardErrorPath = "/Users/alex/Library/Logs/lms-server.err.log";
        };
      };
    };

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
