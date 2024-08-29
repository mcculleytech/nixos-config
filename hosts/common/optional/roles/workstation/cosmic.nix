{pkgs, lib, ... }: {
	services.desktopManager.cosmic.enable = true;
	#services.displayManager.cosmic-greeter.enable = true;

	# defer power management to system76 for cosmic options 
	services.power-profiles-daemon.enable = lib.mkForce false;
	hardware.system76.enableAll = true;

	environment.systemPackages = (with pkgs; [
	  unstable.zafiro-icons
	]);
}