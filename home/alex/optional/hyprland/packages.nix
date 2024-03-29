{ pkgs, ... }: {

	home.packages = with pkgs; 
	[
		wofi
		hyprpaper
		swaynotificationcenter
		playerctl
		brightnessctl
		swayidle
		sway-audio-idle-inhibit
		networkmanagerapplet
		kanshi
		gnome.nautilus
	];
}