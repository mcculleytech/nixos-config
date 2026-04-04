{ config, lib, pkgs, ... }:
{
  options = {
    auto-deploy.enable = lib.mkEnableOption "automatic deployment on new commits";
  };

  config = lib.mkIf config.auto-deploy.enable {

    systemd.services.auto-deploy = {
      description = "Auto-deploy nixos-config on new commits";
      path = with pkgs; [ git colmena openssh curl nix util-linux ];
      serviceConfig = {
        Type = "oneshot";
        User = "alex";
        ExecStart = "/home/alex/Repositories/nixos-config/scripts/auto-deploy.sh";
      };
    };

    systemd.timers.auto-deploy = {
      description = "Run auto-deploy hourly";
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnCalendar = "hourly";
        Persistent = true;
        RandomizedDelaySec = "5m";
      };
    };
  };
}
