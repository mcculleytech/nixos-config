{config, pkgs, ... }: {

	home.pointerCursor = {
	  gtk.enable = true;
	  # x11.enable = true;
	  package = pkgs.gnome.adwaita-icon-theme;
	  name = "Adwaita";
	  size = 18;
	};

	gtk = {
	  enable = true;
	  theme = {
	    package = pkgs.nordic;
	    name = "Nordic-darker";
	  };

	  iconTheme = {
	    package = pkgs.unstable.zafiro-icons;
	    name = "Zafiro-Icons-Dark";
	  };

	  font = {
	    name = "FiraCode";
	    size = 11;
	  };
	};

	# services.xsettingsd = {
	#     enable = true;
	#     settings = {
	#       "Net/ThemeName" = "${config.gtk.theme.name}";
	#       "Net/IconThemeName" = "${config.gtk.iconTheme.name}";
	#     };
	#   };

	  #xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];
}