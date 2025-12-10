{ lib, pkgs, inputs, config, ... }:{

  services.desktopManager.cosmic.enable = true;
  services.displayManager.cosmic-greeter.enable = true;

    environment.systemPackages = with pkgs; 
    [
      unstable.cosmic-ext-tweaks
      unstable.zafiro-icons
    ];

  xdg.portal.enable = true;
  xdg.portal.extraPortals = with pkgs; [
    xdg-desktop-portal-gtk
    xdg-desktop-portal-wlr
  ];

  environment.sessionVariables.COSMIC_DATA_CONTROL_ENABLED = 1;
  
}
