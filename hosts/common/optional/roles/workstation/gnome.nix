{pkgs, ... }: {

  # Enable Gnome
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";
  services.xserver.displayManager.gdm.enable = true;
  services.xserver.desktopManager.gnome.enable = true;

  programs.dconf.enable = true;

  environment.gnome.excludePackages = (with pkgs; [
    gnome-photos
    gnome-tour
    gnome-text-editor # text editor
    gnome-console
  ]) ++ (with pkgs.gnome; [
    cheese # webcam tool
    gnome-music
    epiphany # web browser
    geary # email reader
    evince # document viewer
    gnome-characters
    totem # video player
    tali # poker game
    iagno # go game
    hitori # sudoku game
    atomix # puzzle game
  ]);

  environment.systemPackages = (with pkgs; [
    zafiro-icons
  ]) ++ (with pkgs.gnome; [
    gnome-tweaks
    gnome-screenshot
  ]);



}
