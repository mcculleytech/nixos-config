{

    imports = [
      ./global
    ];

  programs.zsh = {
    shellAliases= {
      os-rebuild   = "export HOSTNAME=$(hostname); sudo nixos-rebuild switch --flake '/home/alex/Repositories/nixos-config/#achilles'";
      home-rebuild = "export HOSTNAME=$(hostname); home-manager switch --flake '/home/alex/Repositories/nixos-config/#alex@achilles'";
    };
  };

}