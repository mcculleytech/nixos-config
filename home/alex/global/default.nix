{ inputs, lib, config, pkgs, outputs, osConfig ? null, ... }:
let
  # Hermes-agent runs on a single host today (saruman). When that's true,
  # `hermes profile create coder` puts a launcher at ~/.local/bin/coder
  # that exec's the local hermes binary. On hosts without hermes-agent
  # the launcher would resolve to nothing, so gate the wrapper + PATH
  # entry on the host actually running it. Falls open (=false) for
  # standalone home-manager invocations where osConfig isn't passed in.
  hermesAgentEnabled = (osConfig.hermes-agent.enable or false);
in
{
  imports = [
    ./git.nix
    ./vim.nix
    ./opencode.nix
    ./tmux.nix
  ];

  home = {
    username = "alex";
    homeDirectory = if pkgs.stdenv.isDarwin then "/Users/alex" else "/home/alex";
  };

  # Hermes `coder` profile launcher. The 1-line wrapper goes into the
  # nix store via home.file (symlinked into ~/.local/bin); the profile
  # state (SOUL.md, config.yaml, memory, sessions, learned skills)
  # stays user-mutable under ~/.hermes/profiles/coder/ because it's
  # runtime-accumulated, not declarative.
  #
  # We also install `hermes` itself into alex's user packages on the
  # same hosts — the systemd service uses its own wrapped venv at
  # /nix/store/...-hermes-agent-env/bin/hermes, but that's not on user
  # PATH. Without this, the `coder` wrapper can't find `hermes` to exec.
  # Keep Go's GOPATH out of $HOME (default would be ~/go). Same place go
  # actually writes to once the env var is set — `go install` lands binaries
  # in $GOPATH/bin, which is added to PATH below.
  home.sessionVariables.GOPATH = "$HOME/.local/share/go";
  home.sessionPath =
    [ "$HOME/.local/share/go/bin" ]
    ++ lib.optionals hermesAgentEnabled [ "$HOME/.local/bin" ];
  home.packages =
    (lib.optionals hermesAgentEnabled [
      inputs.hermes-agent.packages.${pkgs.stdenv.hostPlatform.system}.default
    ])
    # AI coding agents alex uses interactively. claude-code is already on
    # PATH (via the systemPackages route on saruman / hermes' extraPackages),
    # but opencode lives only in nixpkgs and isn't installed anywhere else.
    ++ (lib.optionals pkgs.stdenv.isLinux [ pkgs.unstable.opencode ]);
  home.file = lib.optionalAttrs hermesAgentEnabled {
    ".local/bin/coder" = {
      executable = true;
      text = ''
        #!/bin/sh
        exec hermes -p coder "$@"
      '';
    };
  };

  # Enable home-manager's bash integration so `home.sessionPath` actually
  # lands in alex's interactive PATH. Without this, hm-session-vars.sh
  # exists but nothing sources it on bash login → ~/.local/bin (where
  # the coder wrapper lives) stays invisible. Pairs with the zsh
  # integration that's already on via optional/zsh.nix.
  programs.bash.enable = true;

  nixpkgs = {
    overlays = [
    outputs.overlays.additions
    outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
      permittedInsecurePackages = [
        "electron-27.3.11" # needed for logseq (legacy bundle)
        "electron-39.8.10" # needed for current logseq build
      ];
    };
  };

  # Enable home-manager and git
  programs.home-manager.enable = true;

  # Nicely reload system units when changing configs (Linux/systemd only)
  systemd.user.startServices = lib.mkIf pkgs.stdenv.isLinux "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";

}
