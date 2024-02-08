{

  environment = {
    variables = {
      EDITOR = "vim";
    };
    shellAliases = {
      ga           = "git add .";
      gcm          = "git commit -m";
      gs           = "git status";
      os-rebuild   = "sudo nixos-rebuild switch --flake '/home/alex/Repositories/nixos-config/#'$(hostname)";
      home-rebuild = "home-manager switch --flake '/home/alex/Repositories/nixos-config/#alex@'$(hostname)";
    };
  };


}

