{ inputs, lib, config, pkgs, outputs, osConfig ? null, ... }:
{
  imports = [
    ./git.nix
    ./vim.nix
    ./opencode.nix
    ./tmux.nix
  ];

  home = {
    username = "alex";
    homeDirectory = "/home/alex";
  };

  # Keep Go's GOPATH out of $HOME (default would be ~/go). Same place go
  # actually writes to once the env var is set — `go install` lands binaries
  # in $GOPATH/bin, which is added to PATH below.
  home.sessionVariables.GOPATH = "$HOME/.local/share/go";
  # ~/.local/bin is the standard user bindir and is populated on every host:
  # pipx shims (impacket, bbot, bofhound, ...) and self-updating agent
  # installers like cursor-agent both drop launchers there. It has to live
  # here rather than in ~/.zshrc, which home-manager owns as a read-only nix
  # store symlink.
  home.sessionPath = [
    "$HOME/.local/share/go/bin"
    "$HOME/.local/bin"
  ];
  home.packages = [
    # AI coding agents alex uses interactively. claude-code comes from
    # home/alex/saruman.nix and desktop-packages.nix; opencode lives only in
    # nixpkgs and isn't installed anywhere else.
    pkgs.unstable.opencode
    # superfile: TUI file manager.
    pkgs.superfile
  ];

  # Enable home-manager's bash integration so `home.sessionPath` actually
  # lands in alex's interactive PATH. Without this, hm-session-vars.sh
  # exists but nothing sources it on bash login → ~/.local/bin stays
  # invisible. Pairs with the zsh integration that's already on via
  # optional/zsh.nix.
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
  systemd.user.startServices = "sd-switch";

  # https://nixos.wiki/wiki/FAQ/When_do_I_update_stateVersion
  home.stateVersion = "23.11";

}
