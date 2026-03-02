{pkgs, lib, config, ... }: {

	options = {
		waydroid.enable =
			lib.mkEnableOption "enables waydroid";
	};

	config = lib.mkIf config.waydroid.enable {
		virtualisation.waydroid = {
		  enable = true;
		  package = pkgs.waydroid-nftables;
		};
		environment.systemPackages = [
			pkgs.waydroid-helper
		];
	};

}
