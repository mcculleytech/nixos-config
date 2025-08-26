{ pkgs, ... }: {

  home.packages = (with pkgs.gnomeExtensions; [
    dash-to-dock
    dash-to-panel
    vitals
    user-themes
    tray-icons-reloaded
    fullscreen-avoider
    tiling-shell
  ]);

  gtk = {
    enable = true;

    iconTheme = {
      name = "Zafiro-icons-Dark";
      package = pkgs.unstable.zafiro-icons;
    };

    theme = {
      name = "Nordic-darker-standard-buttons";
      package = pkgs.nordic;
    };

    cursorTheme = {
      name = "Adwaita";
      package = pkgs.unstable.adwaita-icon-theme;
    };
    gtk3 = {
      extraConfig = {
        gtk_application_prefer_dark_theme = "1";
      };
    };
  };

  dconf.settings = {
    "org/gnome/desktop/interface" = {
      color-scheme = "prefer-dark";
      enable-hot-corners = false;
    };

    "org/gnome/shell" = {
      disable-user-extensions = false;
      favorite-apps = [
        "firefox.desktop"
        "brave-browser.desktop"
        "org.gnome.Nautilus.desktop" 
        "terminator.desktop"
        "obsidian.desktop"
        # "vmware-workstation.desktop"
        "virt-manager.desktop"
        "beepertexts.desktop"
        "sublime_text.desktop"
        "bitwarden.desktop"
        "spotify.desktop"
        "ghidra.desktop"
        #"org.remmina.Remmina.desktop"
        "proton-mail.desktop"
      ];
      enabled-extensions = [
        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "dash-to-dock@micxgx.gmail.com"
        "trayIconsReloaded@selfmade.pl"
        "Vitals@CoreCoding.com"
        "tilingshell@ferrarodomenico.com"
        "fullscreen-avoider@noobsai.github.com"
      ];
    };

    "org/gnome/shell/extensions/user-theme" = {
       name = "Nordic-darker-standard-buttons";
    };

    "org/gnome/shell/extensions/dash-to-dock" = { 
      running-indicator-style = "DOTS";
    };

    "org/gnome/mutter" = {
      edge-tiling = true;
    };

    "org/gnome/desktop/interface" = {
      clock-show-weekday = true;
      clock-show-seconds = true;
    };

    "org/gnome/desktop/calendar" = {
      show-weekdate = true;
    };

    "org/gnome/desktop/wm/preferences" = {
      button-layout = "appmenu:minimize,maximize,close";
    };

    "org/gnome/shell/extensions/dash-to-dock" = {
      multi-monitor = true;
    };
  
  };
}
