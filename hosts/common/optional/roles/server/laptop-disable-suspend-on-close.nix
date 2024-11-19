{ config, lib, ... }: {

  options = {
		laptop-disable-suspend-on-close.enable =
			lib.mkEnableOption "disables suspend on laptop when lid is closed";
	};

  config = lib.mkIf config.laptop-disable-suspend-on-close.enable {
    # This module will allow for the laptop to stay on while the server keeps running when the lid is closed.
    # Also turns the screen off.
    services = {  # Power management.
      logind = {
        lidSwitch = "ignore";
        extraConfig = ''
          HandlePowerKey=ignore
        '';
      };
      acpid = {
        enable = true;
        lidEventCommands =
        ''
          export PATH=$PATH:/run/current-system/sw/bin

          lid_state=$(cat /proc/acpi/button/lid/LID0/state | awk '{print $NF}')
          if [ $lid_state = "closed" ]; then
          # Set brightness to zero
          echo 0  > /sys/class/backlight/acpi_video0/brightness
          else
          # Reset the brightness
          echo 50  > /sys/class/backlight/acpi_video0/brightness
          fi
        '';

        powerEventCommands =
        ''
          systemctl suspend
        '';
      };
    };
  };
}
