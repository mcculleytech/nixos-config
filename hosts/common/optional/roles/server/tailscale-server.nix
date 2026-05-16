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
      after = [ "network-pre.target" "tailscale.service" ];
      wants = [ "network-pre.target" "tailscale.service" ];
      wantedBy = [ "multi-user.target" ];

      # set this service as a oneshot job
      serviceConfig.Type = "oneshot";

      # have the job run this shell script
      script = with pkgs; ''
        # wait for tailscaled to settle
        sleep 2

        # authenticate if not already
        status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
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
