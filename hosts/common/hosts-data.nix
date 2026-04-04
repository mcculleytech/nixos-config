# Centralized host inventory — single source of truth for all IPs.
# Used by both the NixOS module (hosts/common/global/hosts.nix) and colmena.nix.
{
  # NixOS managed hosts
  atreides = { ip = "10.1.8.129"; role = "server"; };
  phantom  = { ip = "10.1.8.121"; role = "server"; };
  saruman  = { ip = "10.1.8.6";   role = "server"; };
  vader    = { ip = "10.2.1.245"; role = "server"; };

  # Infrastructure (not NixOS-managed)
  unifi          = { ip = "10.1.8.1";   role = "infrastructure"; };
  truenas        = { ip = "10.1.8.4";   role = "infrastructure"; };
  proxmox        = { ip = "10.3.29.2";  role = "infrastructure"; };
  ilo            = { ip = "10.3.29.4";  role = "infrastructure"; };
  prdcoffeeubuntu = { ip = "10.2.1.6";  role = "infrastructure"; };
}
