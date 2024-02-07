{ pkgs, ... }: {
users.users.alex = {
      shell = pkgs.bash;
    };
}
