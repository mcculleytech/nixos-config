{ lib, ... }: {
  # NM restarts mid-switch during rebuilds, causing nm-online to timeout
  # and report a spurious failure (exit code 4). Nothing depends on this
  # service that doesn't work fine without it.
  systemd.services.NetworkManager-wait-online.enable = lib.mkDefault false;
}
