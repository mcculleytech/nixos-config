{ pkgs, ... }: {

	home.packages = with pkgs; 
	[
		wofi
		swaynotificationcenter
		playerctl
		hyprpaper
		brightnessctl
		sway-audio-idle-inhibit
		networkmanagerapplet
		wdisplays
		gnome.nautilus
		unstable.grimblast
		eww
	];
}