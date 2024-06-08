{ pkgs, ... }: {

	home.packages = with pkgs; 
	[
		wofi
		swaynotificationcenter
		playerctl
		brightnessctl
		sway-audio-idle-inhibit
		networkmanagerapplet
		kanshi
		gnome.nautilus
		unstable.grimblast
		unstable.hyprpaper
		unstable.hyprlock
		unstable.hypridle
		eww
	];
}