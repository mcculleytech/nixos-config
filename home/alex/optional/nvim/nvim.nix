{pkgs, ... }: {
	programs.nixvim = {
		enable = true;
		enableMan = true;

		# Keep files local to config. Path of least resistance to get lazyvim setup
		# git clone https://github.com/LazyVim/starter ~/.config/nvim
		
	};
}