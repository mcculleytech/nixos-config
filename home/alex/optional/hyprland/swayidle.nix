{ config, pkgs, lib, ...}: 
let
 swaylock = "${config.programs.swaylock.package}/bin/swaylock";
 hyprctl = "${config.wayland.windowManager.hyprland.package}/bin/hyprctl";
in
{
	services.swayidle = {
		enable = true;
		systemdTarget = "hyprland-session.target";
	    timeouts = [
	      {
	        timeout = 50;
	        command = ''${hyprctl} notify -1 10000 "rgb(ff1ea3)" "Locking Screen in 10s"'';
	      }
	      {
	        timeout = 60;
	        command = "${swaylock} -S ${config.home.homeDirectory}/.config/swaylock/config -fF";
	      }
	      {
	        timeout = 300;
	        command = ''${hyprctl} dispatch dpms off'';
	        resumeCommand = ''${hyprctl} dispatch dpms on'';
	      }
	    ];
	    events = [
	      {
	        event = "before-sleep";
	        command = "${swaylock } -S ${config.home.homeDirectory}/.config/swaylock/config -fF";
	      }
	      {
	        event = "lock";
	        command = "${swaylock} -S ${config.home.homeDirectory}/.config/swaylock/config -fF";
	      }
	    ];
	  };
	}