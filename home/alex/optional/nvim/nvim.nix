# LazyVim in Nix — neovim + runtime deps managed by nix, plugin config via lazy.nvim
{pkgs, ... }: {
  programs.neovim = {
    enable = true;
    viAlias = true;
    vimAlias = true;
    defaultEditor = true;
    extraPackages = with pkgs; [
      gcc
      ripgrep
      fd
      nodejs
      unzip
      curl
      wget
      gnumake
      tree-sitter
      lazygit
      fzf
    ];
  };

  xdg.configFile."nvim" = {
    source = ./config;
    recursive = true;
  };
}
