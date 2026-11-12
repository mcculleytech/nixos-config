{pkgs, lib, config, ... }: {

	options = {
		steam.enable =
			lib.mkEnableOption "enables steam";
	};

	config = lib.mkIf config.steam.enable {

		programs.steam = {
			enable = true;
			# Remote Play: TCP 27036-27037, UDP 27031-27036 + 10400-10401
			remotePlay.openFirewall = true;
			# protontricks-launch for running mod tools (e.g. OpenKH) in a game prefix
			protontricks.enable = true;
		};
		hardware.steam-hardware.enable = true;
	
	};
}
