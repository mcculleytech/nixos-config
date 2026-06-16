{ lib, pkgs, ... }:
{
  imports = [
    ../common/optional/roles/darwin
  ];

  networking.hostName = "faramir";
  networking.computerName = "faramir";

  lab.lmStudio.autoStart = true;
  lab.lmStudio.autoLoadModel = "qwen3-coder-30b-a3b-instruct-mlx";
  # Serve the LM Studio API on faramir's tailnet IP (not 0.0.0.0) so Hermes
  # on saruman can reach Qwen3-Coder via `/model maccoder`, without exposing
  # the unauthenticated endpoint on untrusted networks the laptop roams onto.
  # Mirrors faramir's tailnetIp in hosts-data.nix (darwin lacks lab.hosts).
  lab.lmStudio.serveHost = "100.90.82.127";

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
    "tree"
    "wget"
    "wireshark"
    "zlib"
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
  homebrew.masApps = {
    WireGuard = 1451685025;
    Tailscale = 1475387142;
  };

  time.timeZone = "America/Chicago";
}
