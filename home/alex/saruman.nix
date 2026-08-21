{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      ./optional/terminator.nix
      ./optional/zsh.nix
      ./optional/security-tooling.nix
      ./optional/nvim
    ];

    terminator.enable = true;
    zsh.enable = true;
    security-tooling.enable = true;
    nvim.enable = true;

  home.packages = with pkgs;
  [
    bitwarden-desktop
    #retroarch-Full
    nixos-anywhere
    colmena
    rpcs3
    game-devices-udev-rules
    firefox
    obsidian
    proton-vpn-cli         # official Proton VPN CLI (`protonvpn` binary, NM backend):
                           # `protonvpn login <user>` then `protonvpn connect --cc IT`
    inputs.claude-code.packages.x86_64-linux.default
    unstable.antigravity-cli
    unstable.ollama
    unstable.lmstudio
    unstable.xonotic
    # unstable.jellyfin-media-player
  ];

  services.protonmail-bridge.enable = true;

  # Steam autostart for the headless gaming session. saruman autologins into
  # plasmax11 on seat0 (:0), which is the GPU-backed display; Remote Play
  # captures wherever Steam happens to be running, so it must be that session
  # and not the xrdp one on :10 (which is a software framebuffer — that was the
  # original ~160ms/frame problem). The DISPLAY guard matters: this file applies
  # to every Plasma session alex opens, and two Steam instances on one install
  # fight over the same lock, so it must no-op in the RDP session.
  #
  # The guard lives in a wrapper script rather than inline in Exec=: the Desktop
  # Entry spec treats quotes as reserved characters, so an inline `sh -c '...'`
  # is malformed and KDE silently declines to run it.
  home.file.".config/autostart/steam.desktop".text =
    let
      launcher = pkgs.writeShellScript "steam-gaming-session" ''
        [ "$DISPLAY" = ":0" ] || exit 0
        exec steam -silent
      '';
    in
    ''
      [Desktop Entry]
      Type=Application
      Name=Steam (gaming session)
      Exec=${launcher}
      Terminal=false
      X-GNOME-Autostart-enabled=true
    '';

}
