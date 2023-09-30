{
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
    localVariables = {
      HOSTNAME = "$(hostname)";
    };
    shellAliases = {
      ga           = "git add .";
      gcm          = "git commit -m";
      gs           = "git status";
    };
  };
}
