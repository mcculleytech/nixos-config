{ config, lib, pkgs, ... }:
{
  options = {
    auto-deploy.enable = lib.mkEnableOption "automatic deployment on new commits";
  };

  config = lib.mkIf config.auto-deploy.enable {

    systemd.services.auto-deploy = {
      description = "Auto-deploy nixos-config on new commits";
      path = with pkgs; [ bash git colmena openssh curl nix util-linux ];

      # The deploy script runs *as* this unit's ExecStart, and it drives
      # `colmena apply` (including the rollback path). A switch-to-configuration
      # triggered by that apply — especially a rollback across a nixpkgs version
      # bump, which restarts nearly every unit — would otherwise stop
      # auto-deploy.service mid-apply, SIGTERM the whole cgroup, and kill the
      # in-flight colmena. That left the box half-switched (running gen != boot
      # gen). Leaving this unit untouched during a switch lets the apply finish;
      # a changed unit definition is just picked up by the next hourly run.
      restartIfChanged = false;
      stopIfChanged = false;

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
