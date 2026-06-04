# Block until tailscaled has assigned this node a tailnet IPv4 (or give up
# after ~60s). Used as an ExecStartPre gate for services that resolve their
# own bind address via `tailscale ip -4` at startup. systemd's
# `After=tailscaled.service` only orders process *spawn*, not readiness — on a
# deploy that restarts tailscaled, the daemon is "active" several seconds
# before it has re-established the tunnel and reassigned the IP, so dependent
# services lose the race and exit 1 with `tailscale ip -4: exit status 1`.
{ writeShellApplication, tailscale }:
writeShellApplication {
  name = "wait-tailnet-ip";
  runtimeInputs = [ tailscale ];
  text = ''
    i=0
    while [ "$i" -lt 60 ]; do
      if tailscale ip -4 >/dev/null 2>&1; then
        exit 0
      fi
      i=$((i + 1))
      sleep 1
    done
    echo "wait-tailnet-ip: tailscale ip -4 unavailable after 60s" >&2
    exit 1
  '';
}
