{ config, ... }: {
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    oh-my-zsh = {
      enable = true;
      plugins = [
         "git"
         "sudo"
      ];
      theme = "bira";
    };
  };
}
