{ lib, pkgs, ...}: {
        
  services.tailscale = {
    package = pkgs.unstable.tailscale;
    enable = true;
  };
  systemd.services.tailscaled.wantedBy = lib.mkForce [];
}
