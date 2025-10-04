{ pkgs, lib, inputs, ... }:
{
	home.packages = with pkgs; [
		adw-gtk3
	];

	xdg.configFile."gtk-3.0/settings.ini".text = ''
	[Settings]
	gtk-theme-name=adw-gtk3
	'';
}