{ config, ... }: {
  programs.zsh = {
    enable = true;
    enableAutosuggestions = true;
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
