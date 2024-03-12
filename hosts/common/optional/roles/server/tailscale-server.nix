{ lib, pkgs, config, outputs, ...}: {
  services.tailscale.useRoutingFeatures = "server";
  # enable ip forwarding for TS Router.
  boot.kernel.sysctl."net.ipv4.ip_forward" = 1;
  boot.kernel.sysctl."'net.ipv6.conf.all.forwarding" = 1;

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

      # check if we are already authenticated to tailscale
      status="$(${tailscale}/bin/tailscale status -json | ${jq}/bin/jq -r .BackendState)"
      if [ $status = "Running" ]; then # if so, then do nothing
        exit 0
      fi

      # otherwise authenticate with tailscale
      ${tailscale}/bin/tailscale up --authkey file:${config.sops.templates."tskey-reusable".path} --ssh --advertise-routes=10.0.0.0/24,10.1.8.0/24,10.2.1.0/24,10.3.29.0/24
    '';
  };
}