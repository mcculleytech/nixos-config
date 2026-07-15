{ pkgs, config, lib, ... }: {

  options = {
    harmonia.enable = lib.mkEnableOption "enables harmonia binary cache";
  };

  config = lib.mkIf config.harmonia.enable {

    # Signing keypair generated with:
    #   nix-store --generate-binary-cache-key saruman-cache-1 secret public
    # Private half lives in secrets/main.yaml as `harmonia_signing_key`;
    # the public half is in trusted-public-keys in
    # hosts/common/global/nix-settings.nix. The upstream module loads the
    # key via systemd LoadCredential (read as root), so no owner/mode
    # overrides are needed.
    sops.secrets.harmonia_signing_key = {
      restartUnits = [ "harmonia.service" ];
    };

    services.harmonia = {
      cache = {
        enable = true;
        signKeyPaths = [ config.sops.secrets.harmonia_signing_key.path ];
        # Lower than cache.nixos.org's 40 so clients prefer the LAN cache
        # when both have a path.
        settings.priority = 30;
        # Not the default 5000 — OctoPrint already owns that on saruman.
        settings.bind = "[::]:5001";
      };
    };

    # Served to LAN + tailnet directly by IP:port — deliberately no
    # Traefik route or Blocky DNS entry so substitution never depends on
    # the proxy/DNS hosts being up. Integrity comes from the ed25519
    # narinfo signature, not transport.
    networking.firewall.allowedTCPPorts = [ 5001 ];
  };
}
