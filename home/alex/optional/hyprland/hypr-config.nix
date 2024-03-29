{
  wayland.windowManager.hyprland = { 
    enable = true;
    settings = {
      autogenerated = 0;
      "$mod" = "SUPER";
      "monitor"="eDP-1, 2560x1600m, 0x0, 1";
      bind = 
      [
        "$mod, RETURN, exec, terminator"
        "$mod, Q, exec, killactive"

      ]
      ++ (
        # workspaces
        # binds $mod + [shift +] {1..10} to [move to] workspace {1..10}
        builtins.concatLists (builtins.genList (
            x: let
              ws = let
                c = (x + 1) / 10;
              in
                builtins.toString (x + 1 - (c * 10));
            in [
              "$mod, ${ws}, workspace, ${toString (x + 1)}"
              "$mod SHIFT, ${ws}, movetoworkspace, ${toString (x + 1)}"
            ]
          )
          10)
      );
    };
  };

}
