{ pkgs,... }: {
users.users.alex = {
      shell = pkgs.zsh;
    };
}
