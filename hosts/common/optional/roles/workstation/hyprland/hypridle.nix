{ pkgs, ...}:{
	services.hypridle = {
		enable = true;
		serviceConfig = {
			ExecStart = "${pkgs.hyprlock}/bin/hyprlock ${pkgs.hypridle}/bin/hypridle-start";
		};
	};
}