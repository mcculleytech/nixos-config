{ pkgs, lib, config, ... }:

{
 	options = {
		qemuGuest.enable =
			lib.mkEnableOption "enables qemu agent for virtual machines";
	};

	config = lib.mkIf config.qemuGuest.enable {
	   services.qemuGuest.enable = true;
	};
}
