{ pkgs, ... }: {

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
        "org.gnome.Nautilus.desktop" 
        "terminator.desktop"
        "obsidian.desktop"
        "virt-manager.desktop"
        "element-desktop.desktop"
        "beeper.desktop"
        "sublime_text.desktop" 
        "bitwarden.desktop"
        "spotify.desktop"
      ];
      enabled-extensions = [

        "user-theme@gnome-shell-extensions.gcampax.github.com"
        "dash-to-dock@micxgx.gmail.com"
        "trayIconsReloaded@selfmade.pl"
        "Vitals@CoreCoding.com"

      ];
    };

    "org/gnome/shell/extensions/user-theme" = {
       name = "Nordic-darker-standard-buttons";
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

  home.packages = (with pkgs.gnomeExtensions; [
    dash-to-dock
    dash-to-panel
    vitals
    user-themes
    tray-icons-reloaded
  ]); 

}
