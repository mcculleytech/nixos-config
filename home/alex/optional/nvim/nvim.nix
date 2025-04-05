{pkgs, ... }: {
	programs.nixvim = {
		enable = true;

	  	colorschemes.nord.enable = true;
	  	opts = {
	  		number = true;         # Show line numbers
	  		shiftwidth = 2;        # Tab width should be 2
	  	};
	};
}