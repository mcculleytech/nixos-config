{pkgs, ... }: {
	programs.nixvim = { 
		plugins = { 
			treesitter.enable = true;
			lsp.enable = true;
			telescope.enable = true;
		};
	};
}