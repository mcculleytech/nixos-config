{config, ...}: {
	programs.waybar = {
		enable = true;
		systemd = {
			enable = true;
			target = "hyprland-session.target";
		};
        style = ./style.css;
		settings = {
		  mainBar = {
		  	gtk-layer-shell = true;
		    layer = "top";
		    position = "top";
		    height = 30;
		    spacing = 18;
		    # output = [
		    #   "eDP-1"
		    # ];
		    modules-left = [ "hyprland/workspaces" ];
		    modules-center = [ "memory" "clock" "cpu" ];
		    modules-right = [ "pulseaudio" "idle_inhibitor" "backlight" "battery" "network" "tray" ];

		    "hyprland/workspaces" = {
		      format = "{icon}";
		      on-click = "activate";
		      active-only = false;
		      format-icons = {
		      	"1" = "";
		      	"2" = "";
		      	"3" = "";
		      	"4" = "";
		      	"5" = "";
		      };
		      sort-by-number = true;
		    };
		    battery = {
		        format = "{capacity}% - {time} {icon}";
		        format-charging = "{capacity}%";
		        format-icons = ["" "" "" "" ""];
		        interval = 30;
		    };
		    backlight = {
		        format = "{percent}% {icon}";
		        format-icons= [ "" ""];
		        reverse-scrolling = true;
		    };
		    clock = {
		        format = "{:%A, %B %d, %Y (%R)}  ";
		        tooltip-format = "<tt><big>{calendar}</big></tt>";
		        calendar = {
		           mode = "month";
		           weeks-pos = "right";
		           on-scroll = 1;
		           format = {
		             months = "<span color='#ffead3'><b>{}</b></span>";
		             days =  "<span color='#ecc6d9'><b>{}</b></span>";
		             weeks =  "<span color='#99ffdd'><b>W{}</b></span>";
		             weekdays = "<span color='#ffcc66'><b>{}</b></span>";
		             today = "<span color='#ff6699'><b><u>{}</u></b></span>";
		           };
		        };
		    };
		    idle_inhibitor = {
		        format = "{icon}";
		        format-alt = "{icon} idle {status}";
		        format-alt-click = "click-right";
		        format-icons = {
		            activated = "";
		            deactivated = "";
		        };
		        tooltip = false;		    
		    };
		    cpu = {
		        interval = 10;
		        format = "{}% ";
		        max-length = 10;
		    };
		    memory = {
		        interval = 30;
		        format = "{}% ";
		        max-length = 10;
		    };
		    tray = {
		        icon-size = 21;
		        spacing = 10;
		    };
		    network = {
		        interface = "wlp1s0";
		        format = "{ifname}";
		        format-wifi = "{essid} ({signalStrength}%) ";
		        format-ethernet = "{ipaddr}/{cidr} 󰊗";
		        format-disconnected = ""; #An empty format will hide the module.
		        tooltip-format = "{ifname} via {gwaddr} 󰊗";
		        tooltip-format-wifi = "{essid} ({signalStrength}%) ";
		        tooltip-format-ethernet = "{ifname} ";
		        tooltip-format-disconnected = "Disconnected";
		        max-length = 50;
		    };
		    pulseaudio = {
		        format = "{volume}% {icon}";
		        format-bluetooth = "{volume}% {icon}";
		        format-muted = "";
		        format-icons = {
		            headphone= "";
		            hands-free= "";
		            headset= "";
		            phone= "";
		            portable= "";
		            car= "";
		            default= ["" ""];
		        };
		        scroll-step = 1;
		        on-click = "pavucontrol";
		        ignored-sinks = ["Easy Effects Sink"];
		    };
	    };
	  };
	};
}
