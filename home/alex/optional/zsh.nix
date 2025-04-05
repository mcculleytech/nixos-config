{ config, ... }: {
  programs.zsh = {
    enable = true;
    autosuggestion.enable = true;
    shellAliases = {
      gdb-super = "gdb --batch --ex run bt --ex q --args";
    };
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
