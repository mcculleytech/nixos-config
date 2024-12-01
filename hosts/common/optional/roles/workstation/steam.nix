{pkgs, lib, config, ... }: {

	options = {
		steam.enable =
			lib.mkEnableOption "enables steam";
	};

	config = lib.mkIf config.steam.enable {

		programs.steam = {
			enable = true;
		};
		hardware.steam-hardware.enable = true;
	
	};
}