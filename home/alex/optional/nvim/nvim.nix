{pkgs, ... }: {
	programs.nixvim = {
		enable = true;

	  	colorschemes.nord.enable = true;
	  	plugins.lualine.enable = true;
	};
}