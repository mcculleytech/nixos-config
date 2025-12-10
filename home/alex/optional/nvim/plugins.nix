{pkgs, ... }: {
	programs.nixvim = { 
		plugins = { 
			# lualine.enable = true;
			# treesitter.enable = true;
			# lsp.enable = true;
			# telescope.enable = true;
			# autoclose.enable = true;
			# web-devicons.enable = true;
		};
	};
}