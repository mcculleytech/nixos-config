{ pkgs, ... }: {
	programs.swaylock = {
    	enable = true;
    	package = pkgs.swaylock-effects;
    	settings = {
      		effect-blur = "20x3";
      		fade-in = 0.1;
      	};
    };

    # need to add swaylock to pam, that's in the hyprland system config file
}