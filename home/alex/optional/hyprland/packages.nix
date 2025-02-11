{ pkgs, ... }: {

	home.packages = with pkgs; 
	[
		wofi
		swaynotificationcenter
		playerctl
		hyprpaper
		hyprlock
		hypridle
		hyprcursor
		brightnessctl
		sway-audio-idle-inhibit
		networkmanagerapplet
		wdisplays
		nautilus
		unstable.grimblast
		eww
		udiskie
	];
}