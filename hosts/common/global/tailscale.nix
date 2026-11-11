{ lib, pkgs, config, outputs, ...}: {


  sops.secrets.tskey-reusable = {};
  sops.templates."tskey-reusable".content = ''
    ${config.sops.placeholder.tskey-reusable}
  '';

  services.tailscale = {
    package = pkgs.unstable.tailscale;
    enable = true;
  };

  environment.persistence = {
    "/persist" = {
    hideMounts = true;
      directories = [
        "/var/lib/tailscale"
      ];
    };
  };

  systemd.services.tailscale-autoconnect = {
    description = "Automatic connection to Tailscale";

    # make sure tailscale is running before trying to connect to tailscale
    after = [ "network-pre.target" "tailscale.service" ];
    wants = [ "network-pre.target" "tailscale.service" ];
    wantedBy = [ "multi-user.target" ];

    # set this service as a oneshot job
    serviceConfig.Type = "oneshot";

    # have the job run this shell script
    script = let
      tailscale = config.services.tailscale.package;
    in ''
      # Wait for the daemon to answer rather than a blind `sleep 2` — on a cold
      # boot tailscaled is still starting, `tailscale status` returns nothing and
      # the test below then dies with "unary operator expected".
      tries=0
      while [ "$tries" -lt 30 ]; do
        ${tailscale}/bin/tailscale status -json >/dev/null 2>&1 && break
        sleep 1
        tries=$((tries + 1))
      done

      # check if we are already authenticated to tailscale
      status="$(${tailscale}/bin/tailscale status -json 2>/dev/null | ${pkgs.jq}/bin/jq -r .BackendState 2>/dev/null || echo unknown)"
      if [ "$status" = "Running" ]; then # if so, then do nothing
        exit 0
      fi

      # otherwise authenticate with tailscale
      ${tailscale}/bin/tailscale up --authkey file:${config.sops.templates."tskey-reusable".path} --ssh --reset
    '';
  };
}
