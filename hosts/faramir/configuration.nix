{ lib, pkgs, ... }:
{
  imports = [
    ../common/optional/roles/darwin
  ];

  networking.hostName = "faramir";
  networking.computerName = "faramir";

  # LM Studio runs here as a GUI app only, serving loopback 127.0.0.1:1234 for
  # opencode (see home/alex/global/opencode.nix). The old `lab.lmStudio` module
  # tried to headlessly bind it to the tailnet for Hermes — removed 2026-08-07,
  # it never worked: `lms` 0.4.19 has no `--host` flag, RunAtLoad raced ahead of
  # the tailnet interface (EADDRNOTAVAIL), and `lms load` hung on an interactive
  # picker under launchd. Re-exposing it needs a reverse proxy, not a flag.

  # Homebrew declaration for faramir. The darwin role pins
  # `homebrew.onActivation.cleanup = "none"`, so this list is treated as
  # *additive* — packages here are installed/upgraded; anything outside
  # the list is left alone. Imperative `brew install …` remains safe.
  #
  # The lists below mirror everything currently user-requested on faramir
  # as of 2026-05-20 (snapshot after the cleanup="zap" incident wiped
  # 48 casks + 190 formulae). Add to or trim from here as the system
  # evolves; refresh via `brew list --installed-on-request` + `brew tap`.

  homebrew.taps = [
    "anomalyco/tap"
    "azure/functions"
    "hashicorp/tap"
    "hudochenkov/sshpass"
  ];

  homebrew.brews = [
    "age"
    "angband"
    "ansible"
    "automake"
    "awscli"
    "azure-cli"
    "azure/functions/azure-functions-core-tools@4"
    "bat"
    "beads"
    "bitwarden-cli"
    "cask"
    "cdrtools"
    "cmatrix"
    "container"
    "curl"
    "direnv"
    "doctl"
    "exif"
    "expat"
    "fd"
    "ffmpeg"
    "fzf"
    "gastown"
    "gawk"
    "gh"
    "git"
    "git-crypt"
    "glab"
    "glances"
    "gmp"
    "gnu-sed"
    "gnupg"
    "go"
    "gradle"
    "hashcat"
    "htop"
    "hugo"
    "isl"
    "john"
    "jq"
    "libmpc"
    "libtool"
    "make"
    "mingw-w64"
    "mpfr"
    "nasm"
    "neovim"
    "nmap"
    "node"
    "anomalyco/tap/opencode"
    "openvpn"
    "p7zip"
    "hashicorp/tap/packer"
    "pgvector"
    "pi-coding-agent"
    "pipx"
    "postgresql@15"
    "postgresql@18"
    "potrace"
    "python@3.12"
    "python@3.13"
    "ripgrep"
    "rust"
    "rustscan"
    "sdl2"
    "sevenzip"
    "sops"
    "hudochenkov/sshpass/sshpass"
    "starship"
    # superfile installs its binary as `spf`, not `superfile` (the nixpkgs
    # build used the long name).
    "superfile"
    "hashicorp/tap/terraform"
    # tmux came from home-manager's `programs.tmux` module until Phase 2 of the
    # Mac/Nix decouple. Unlike zsh, vim and bash there is no macOS-shipped
    # fallback, so dropping the module took tmux off PATH entirely — it has to
    # be declared here. Config lives in ~/.tmux.conf.
    "tmux"
    "tree"
    # nvim-treesitter's `main` branch compiles parsers with the tree-sitter
    # CLI, which the `tree-sitter` formula no longer ships (it is now just
    # libtree-sitter). Without this, every `:TSUpdate` fails silently and
    # parsers drift out of sync with Neovim's bundled queries.
    "tree-sitter-cli"
    "wget"
    "wireshark"
    "yq"
    "zlib"
    # Sourced by ~/.zshrc from
    # /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh.
    # oh-my-zsh itself is NOT a brew formula — it stays as the ~/.oh-my-zsh
    # checkout that predates the decouple.
    "zsh-autosuggestions"
  ];

  homebrew.casks = [
    "arduino-ide"
    "balenaetcher"
    "beeper"
    "bitwarden"
    "brave-browser"
    "chatgpt"
    "claude"
    "claude-code"
    "cmux"
    "codex"
    "container"
    "discord"
    "firefox"
    "flameshot"
    "font-0xproto-nerd-font"
    "ghostty"
    "gimp"
    "godot"
    "inkscape"
    "iterm2"
    "microsoft-auto-update"
    "microsoft-excel"
    "microsoft-outlook"
    "microsoft-powerpoint"
    "microsoft-teams"
    "microsoft-word"
    "miniconda"
    "obsidian"
    "onedrive"
    "opencode-desktop"
    "postman"
    "proton-drive"
    "proton-mail"
    "protonvpn"
    "raspberry-pi-imager"
    "rectangle"
    "signal"
    "spotify"
    "sublime-text"
    "transmission"
    "ultimaker-cura"
    "vmware-fusion"
    "windows-app"
  ];

  # Mac App Store apps. nix-darwin drives these via the `mas` CLI; faramir
  # must be signed into the App Store with the Apple ID that originally
  # acquired each app, or `mas install` fails with "not purchased".
  # GarageBand intentionally omitted.
  #
  # Tailscale is MAS-only here — do NOT also add the `tailscale` brew formula.
  # The formula ships its own root tailscaled (via a LaunchDaemon) which grabs
  # /var/run/tailscaled.socket and fights the MAS app's network extension: the
  # CLI then talks to the formula's logged-out daemon while the app can't start
  # its CLI bridge, and the node never gets a tailnet IP. Removed 2026-08-07.
  homebrew.masApps = {
    WireGuard = 1451685025;
    Tailscale = 1475387142;
  };

  time.timeZone = "America/Chicago";
}
