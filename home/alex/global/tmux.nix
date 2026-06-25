{ ... }:
{
  # tmux tuned for running TUIs (e.g. Claude Code) in long SSH sessions.
  # tmux's defaults — the legacy `screen` terminal and a 500ms escape-time —
  # are a classic cause of progressive redraw corruption with streaming TUIs;
  # the settings below stabilize rendering.
  programs.tmux = {
    enable = true;
    terminal = "tmux-256color"; # modern terminfo; better than the default `screen`
    escapeTime = 10; # ms — default 500 lets escape sequences mis-parse and glitch the UI
    extraConfig = ''
      # Let TUIs pass escape sequences (progress/notifications) through tmux.
      set -g allow-passthrough on
      # Distinguish Shift+Enter etc. and advertise extended keys to xterm-likes.
      set -s extended-keys on
      set -as terminal-features 'xterm*:extkeys'
    '';
  };
}
