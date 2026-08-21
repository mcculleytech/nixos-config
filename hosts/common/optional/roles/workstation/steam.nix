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
		};
		hardware.steam-hardware.enable = true;
	
	};
}
