{ pkgs, ... }:
let
  flameshot-gui = pkgs.writeShellScriptBin "flameshot-gui" "${pkgs.flameshot}/bin/flameshot gui";
in
{
  dconf.settings = {
    # Disables the default screenshot interface
    "org/gnome/shell/keybindings" = {
      show-screenshot-ui = [ ];
    };
    # Sets the new keybindings
    "org/gnome/settings-daemon/plugins/media-keys" = {
      custom-keybindings = [ "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0/" ];
    };
    # Defines the new shortcut
    "org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom0" = {
      binding = "<Shift><Control>s";
      command = "${flameshot-gui}/bin/flameshot-gui";
      name = "Flameshot";
    };
  };
}