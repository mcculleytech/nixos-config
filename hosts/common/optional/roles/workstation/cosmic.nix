{pkgs, lib, ... }: {
	services.desktopManager.cosmic.enable = true;
	#services.displayManager.cosmic-greeter.enable = true;

	environment.systemPackages = (with pkgs; [
	  unstable.zafiro-icons
	]);
}