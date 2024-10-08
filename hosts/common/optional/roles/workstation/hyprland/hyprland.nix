{inputs, pkgs, ...}:

{

  nix.settings = {
    substituters = ["https://hyprland.cachix.org"];
    trusted-public-keys = ["hyprland.cachix.org-1:a7pgxzMz7+chwVL3/pzj6jIBMioiJM7ypFP8PwtkuGc="];
  };
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
    package = inputs.hyprland.packages.${pkgs.system}.hyprland;
  };
  services.xserver = {
    enable = true;
    displayManager.gdm = {
        enable = true;
        wayland = true;
    };
  };

  fonts.packages = with pkgs; [
    font-awesome
  ];

  # blueman service
  services.blueman.enable = true;

  # add swaylock to PAM
  security.pam.services.swaylock = {};
}
