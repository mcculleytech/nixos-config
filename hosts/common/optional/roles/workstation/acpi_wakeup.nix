{ pkgs, ... }:{
  systemd.services.enable-acpi-wakeup = {
    description = "Enable ACPI wakeup devices";
    wantedBy = [ "multi-user.target" ];
    after = [ "multi-user.target" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = pkgs.writeShellScript "enable-wakeup" ''
        for dev in SWUS XHC0 XHC1 XHC2 XHC3 XHC4 NHI0 NHI1; do
          if grep -q "$dev" /proc/acpi/wakeup; then
            echo "$dev" > /proc/acpi/wakeup
          fi
        done
      '';
    };
  };
}