{ lib, pkgs, config, outputs, ...}:
let
  advertisedRoutes = "10.0.0.0/24,10.1.8.0/24,10.2.1.0/24,10.3.29.0/24";
in
{

options = {
		tailscale-server.enable =
			lib.mkEnableOption "enables tailscale subnet router functionality";
	};
	config = lib.mkIf config.tailscale-server.enable {

    services.tailscale.useRoutingFeatures = "server";
    # enable ip forwarding for TS Router.
    boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
    boot.kernel.sysctl."net.ipv6.conf.all.forwarding" = 1;

    sops.secrets.tskey-reusable = {};
    sops.templates."tskey-reusable".content = ''
      ${config.sops.placeholder.tskey-reusable}
    '';

    systemd.services.tailscale-autoconnect = {
      description = "Automatic connection to Tailscale";

      # make sure tailscale is running before trying to connect to tailscale
      after = [ "network-pre.target" "tailscale.service" "network-online.target" ];
      wants = [ "network-pre.target" "tailscale.service" "network-online.target" ];
      wantedBy = [ "multi-user.target" ];

      # set this service as a oneshot job
      serviceConfig.Type = "oneshot";

      # have the job run this shell script
      script = with pkgs; ''
        # Wait for the daemon to answer instead of a blind `sleep 2`: on a cold
        # boot tailscaled is still coming up, `tailscale status` returns nothing,
        # the check below fails, and the unit dies before the route re-assert at
        # the bottom of this script ever runs.
        tries=0
        while [ "$tries" -lt 30 ]; do
          ${tailscale}/bin/tailscale status -json >/dev/null 2>&1 && break
          sleep 1
          tries=$((tries + 1))
        done

        # authenticate if not already
        status="$(${tailscale}/bin/tailscale status -json 2>/dev/null | ${jq}/bin/jq -r .BackendState 2>/dev/null || echo unknown)"
        if [ "$status" != "Running" ]; then
          ${tailscale}/bin/tailscale up \
            --authkey file:${config.sops.templates."tskey-reusable".path} \
            --ssh \
            --advertise-routes=${advertisedRoutes} \
            --advertise-exit-node \
            --reset
        fi

        # Re-assert subnet-router prefs every boot. `tailscale set` is idempotent;
        # this prevents drift if prefs get cleared via the admin console or a
        # stray `tailscale set --reset` (which silently nuked routes once and
        # took down DNS for off-LAN clients).
        ${tailscale}/bin/tailscale set \
          --advertise-routes=${advertisedRoutes} \
          --advertise-exit-node=true
      '';
    };
	};
}
