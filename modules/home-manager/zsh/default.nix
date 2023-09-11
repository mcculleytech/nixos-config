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
    shellAliases = {
      ga           = "git add .";
      gcm          = "git commit -m";
      gs           = "git status";
      os-rebuild   = "sudo nixos-rebuild switch --flake '/home/alex/Repositories/nixos-config/#achilles'";
      home-rebuild = "home-manager switch --flake '/home/alex/Repositories/nixos-config/#alex@achilles'";
    };
  };
}
