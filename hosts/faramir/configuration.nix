{ lib, pkgs, ... }:
{
  imports = [
    ../common/optional/roles/darwin
  ];

  networking.hostName = "faramir";
  networking.computerName = "faramir";

  lab.lmStudio.autoStart = true;
  lab.lmStudio.autoLoadModel = "qwen/qwen3.6-27b";

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
    "beads"
    "bitwarden-cli"
    "cask"
    "cava"
    "cdrtools"
    "cmatrix"
    "container"
    "doctl"
    "exif"
    "expat"
    "ffmpeg"
    "gastown"
    "gawk"
    "gh"
    "ghidra"
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
    "libmpc"
    "libtool"
    "make"
    "mingw-w64"
    "mpfr"
    "nasm"
    "neovim"
    "nmap"
    "node"
    "ollama"
    "anomalyco/tap/opencode"
    "openvpn"
    "p7zip"
    "hashicorp/tap/packer"
    "pgvector"
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
    "tailscale"
    "hashicorp/tap/terraform"
    "tmux"
    "transmission-cli"
    "tree"
    "wget"
    "wireshark"
    "zlib"
  ];

  # `antigravity` is deliberately omitted — that cask is the legacy
  # Antigravity Desktop App with a broken `agy` shim; the real CLI is
  # the `antigravity-cli` Nix derivation in home-manager. Run
  # `brew uninstall --cask antigravity` once manually to clear it.
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
    "ghidra"
    "ghostty"
    "gimp"
    "google-gemini"
    "inkscape"
    "iterm2"
    "lm-studio"
    "microsoft-auto-update"
    "microsoft-excel"
    "microsoft-outlook"
    "microsoft-powerpoint"
    "microsoft-teams"
    "microsoft-word"
    "miniconda"
    "obsidian"
    "ollama-app"
    "onedrive"
    "opencode-desktop"
    "postman"
    "proton-drive"
    "proton-mail"
    "protonvpn"
    "raindropio"
    "raspberry-pi-imager"
    "rectangle"
    "signal"
    "spotify"
    "sublime-text"
    "transmission"
    "ultimaker-cura"
    "utm"
    "vmware-fusion"
    "windows-app"
    "wispr-flow"
  ];

  time.timeZone = "America/Chicago";
}
