{ ... }:
{
  # Phase 2 of the Mac/Nix decouple (see README ToDo). faramir's dotfiles are
  # hand-written now, so this host deliberately imports NEITHER ./global NOR
  # ./optional/zsh.nix: home-manager is reduced to the scaffolding it needs to
  # evaluate, and manages no files at all. Packages come from homebrew
  # (hosts/faramir/configuration.nix); config lives in ~/.zshrc, ~/.zshenv,
  # ~/.zprofile and ~/.tmux.conf.
  #
  # Deliberately not imported:
  #   ./global           - git.nix (already inert: `enable`/`userName` are
  #                        nested inside `programs.git.settings`, so
  #                        programs.git.enable was never set and ~/.gitconfig
  #                        has been hand-written since Apr 2026), vim.nix
  #                        (bakes config into a wrapped package, no dotfile),
  #                        tmux.nix, opencode.nix
  #   ./optional/zsh.nix - zsh + oh-my-zsh + autosuggestions, now hand-written
  #                        against the ~/.oh-my-zsh checkout already on disk
  #
  # Two things this fixes rather than merely relocates:
  #
  # 1. tmux 3.6 loads ~/.tmux.conf *and* ~/.config/tmux/tmux.conf additively,
  #    and the generated one loaded last -- so tmux.nix's `mode-keys emacs` and
  #    `mouse off` were silently overriding the `vi`/`mouse on` set by hand in
  #    ~/.tmux.conf. Dropping the module restores the intended settings. The
  #    TUI tuning (tmux-256color, escape-time, allow-passthrough, extended-keys,
  #    csi-u) was copied into ~/.tmux.conf first.
  #
  # 2. home-manager's linkGeneration had been silently aborting on this host:
  #    ~/.config/opencode/opencode.json had drifted to a real file while
  #    opencode.json.bak already existed, so backupFileExtension="bak" refused
  #    to clobber the backup and NO home-manager files were relinked (packages
  #    still applied -- they route through the system profile, which is why the
  #    breakage was invisible). opencode owns that file outright now.
  #
  # The direnv `doCheck = false` overlay is gone with the nix direnv package;
  # direnv/starship/fzf are brew formulae now, wired up in ~/.zshrc.

  home.username = "alex";
  home.homeDirectory = "/Users/alex";
  home.stateVersion = "23.11";

  programs.home-manager.enable = true;
}
