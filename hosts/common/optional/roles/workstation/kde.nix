{pkgs, ...}: {
  services.xserver.enable = true;
  services.xserver.xkb.layout = "us";
  services.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma6.enable = true;

   environment.systemPackages = with pkgs; 
   [
    kdePackages.krdc

   ];
}
