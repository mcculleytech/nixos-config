{ pkgs, config, lib, inputs, ... }: {

  options = {
    desktop-packages.enable = lib.mkEnableOption "enables desktop packages";
  };

  config = lib.mkIf config.desktop-packages.enable {
    home.packages = with pkgs;
    [
      spotify
      terminator
      guake
      evince
      nfs-utils
      transmission_4-gtk
      ranger
      vlc
      appimage-run
      wakeonlan
      firefox
      drawing
      rpcs3
      game-devices-udev-rules
      remmina
      ansible
      packer
      brave
      zrok
      calibre
      protonvpn-gui
      watchmate
      unstable.luanti-client
      gparted
      # contact # meshtastic console UI — disabled with meshtastic (below)
      # rpi-imager
      ollama
      arduino-ide
      fastfetch
      # jellyfin-media-player - insecure package, reinstall when updated
      ghostty
      zoom-us
      anki
      yt-dlp
      flameshot
      angband
      protonmail-desktop
      ghidra
      unstable.vmware-workstation
      # python312Packages.meshtastic
      #   Disabled: not needed on the endpoint right now, and it was the sole
      #   thing dragging in a 40-min PyTorch build — its dep chain is
      #   meshtastic → pandas-stubs → tables → blosc2 → torch. Re-enable when
      #   the mesh radio is back in use.
      # software dev packages
      python3
      gnumake
      gcc
      nasm
      gdb
      valgrind
      unstable.devenv
      # Unstable pkgs
      inputs.claude-code.packages.x86_64-linux.default
      unstable.antigravity-cli
      unstable.beeper
      unstable.bitwarden-desktop
      unstable.awscli2
      unstable.terraform
      unstable.hexchat
      unstable.cura-appimage
      unstable.quickemu
      unstable.signal-desktop
      unstable.hugo
      unstable.xonotic
      unstable.obs-studio
      unstable.godot_4
      unstable.distrobox
      unstable.bolt
      unstable.thunderbolt
      unstable.libreoffice-fresh
      unstable.protonmail-bridge
      unstable.obsidian
      unstable.sublime4
      unstable.lmstudio
    ];
  };
}
