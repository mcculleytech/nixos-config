{config, pkgs, ...}: {

    programs.zsh.enable = true;
    users.users.alex = {
      initialPassword = "changeMe!";
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
      ];
      shell = pkgs.zsh;
      extraGroups = [ "wheel" "libvirtd" "audio"];
    };
}
