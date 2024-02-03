{pkgs, ...}: {
  programs.vim = {
    enable = true;
    plugins = with pkgs.vimPlugins; [
      vim-airline
    ];
    settings = {ignorecase = true; };
    extraConfig = ''
      set number
    '';
  };
}
