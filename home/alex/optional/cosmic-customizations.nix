{ pkgs, lib, inputs, config, ... }: {

  options = {
    cosmic-customizations.enable = lib.mkEnableOption "enables COSMIC desktop customizations";
  };

  config = lib.mkIf config.cosmic-customizations.enable {
    home.packages = with pkgs; [
      adw-gtk3
      nerd-fonts._0xproto
    ];

    xdg.configFile."gtk-3.0/settings.ini".text = ''
      [Settings]
      gtk-theme-name=adw-gtk3
    '';
  };
}
