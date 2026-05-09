{ lib, config, pkgs, outputs, ... }:
{
  imports = [
    ../../ironclaw.nix
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
  };

  config = {
    lab.ironclaw.enable = true;
    lab.ironclaw.fromBrew = true;

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

    environment.systemPackages = with pkgs; [
      curl
      git
      jq
      ripgrep
      fd
      bat
    ] ++ lib.optional (!config.lab.ironclaw.fromBrew) pkgs.ironclaw
      ++ lib.optional config.lab.signalChannel.enable pkgs.signal-cli;

    environment.variables = lib.optionalAttrs config.lab.signalChannel.enable {
      SIGNAL_HTTP_URL = "http://127.0.0.1:${toString config.lab.signalChannel.httpPort}";
    };

    launchd.user.agents = lib.optionalAttrs config.lab.signalChannel.enable {
      signal-cli-http = {
        # signal-cli daemon will fail-fast until you've linked an account via
        # `signal-cli link -n faramir`. KeepAlive lets launchd retry on the
        # default ThrottleInterval (10s) so it picks up the account once
        # registration completes.
        command = "${pkgs.signal-cli}/bin/signal-cli daemon --http=127.0.0.1:${toString config.lab.signalChannel.httpPort}";
        serviceConfig = {
          KeepAlive = true;
          RunAtLoad = true;
          StandardOutPath = "/Users/alex/Library/Logs/signal-cli.out.log";
          StandardErrorPath = "/Users/alex/Library/Logs/signal-cli.err.log";
        };
      };
    } // lib.optionalAttrs config.lab.lmStudio.autoStart {
      lms-server = {
        # `lms server start` brings up LM Studio's local API on 127.0.0.1:1234
        # and exits immediately. If autoLoadModel is set, queue a model load so
        # ironclaw has its LLM endpoint warmed up before first request.
        # KeepAlive disabled — the command is one-shot, not a long-running daemon.
        command =
          let
            lms = "/Users/alex/.lmstudio/bin/lms";
            loadCmd = lib.optionalString (config.lab.lmStudio.autoLoadModel != null)
              " && ${lms} load '${config.lab.lmStudio.autoLoadModel}'";
          in
          "/bin/sh -c '${lms} server start${loadCmd}'";
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
        cleanup = "zap";
      };
      taps = [ ];
      brews = lib.optional config.lab.ironclaw.fromBrew "ironclaw";
      casks = [ ];
    };

    users.users.alex = {
      home = "/Users/alex";
    };

    system.primaryUser = "alex";
    system.stateVersion = 6;
  };
}
