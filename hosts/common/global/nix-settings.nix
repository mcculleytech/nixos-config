{ lib, config, inputs, outputs, ... }: {
  nix = {
    registry = lib.mapAttrs (_: value: { flake = value; }) inputs;
    nixPath = lib.mapAttrsToList (key: value: "${key}=${value.flake}") config.nix.registry;

    settings = {
      experimental-features = ["nix-command" "flakes"];
      auto-optimise-store = true;
      # Mid-build GC safety net. When free space on the store volume
      # drops below `min-free`, the daemon triggers an in-band GC that
      # runs until `max-free` is available. Without this, the daemon
      # happily fills the disk then crashes — observed 2026-05-26 when
      # a deploy storm + heavy container image pulls (5GB Speaches,
      # 13.7GB Kokoro) saturated /nix on saruman's 233GB system disk.
      min-free = toString (10 * 1024 * 1024 * 1024);   # 10 GB
      max-free = toString (50 * 1024 * 1024 * 1024);   # 50 GB
      substituters =
        # Harmonia on saruman — first-choice cache of everything saruman
        # has built (it builds the whole fleet via colmena). Uses the
        # tailnet IP, not the LAN IP: roaming laptops (aeneas) and the DMZ
        # (vader) can't reach 10.1.8.x, while tailscale gives everyone a
        # route and negotiates direct peer-to-peer (~LAN speed) for hosts
        # on the same network. Raw IP:port so substitution never depends
        # on blocky/traefik being up. Saruman skips itself: querying your
        # own store over HTTP is a wasted round-trip.
        lib.optionals (config.networking.hostName != "saruman") [
          "http://${config.lab.hosts.saruman.tailnetIp}:5001"
        ]
        ++ [
        "https://cosmic.cachix.org/"
        "https://nix-community.cachix.org"
        "https://install.determinate.systems"
        "https://claude-code.cachix.org"
       ];
      trusted-public-keys = [
        "saruman-cache-1:zemxHp2WafWZoT+oL93fBrOFuc5Y83ZDxiQ5vAJGPzU="
        "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE="
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
        "cache.flakehub.com-3:hJuILl5sVK4iKm86JzgdXW12Y2Hwd5G07qKtHTOcDCM="
        "claude-code.cachix.org-1:YeXf2aNu7UTX8Vwrze0za1WEDS+4DuI2kVeWEE4fsRk="
      ];
      trusted-users = ["root" "alex"];
      stalled-download-timeout = 60;
      connect-timeout = 10;
    };
    gc = {
      automatic = true;
      # Daily cadence (was weekly). A workstation that deploys multiple
      # times a day can fill the store between weekly runs — see
      # 2026-05-26 incident notes in `min-free` comment above.
      dates = "daily";
      # One week of rollback targets retained. Auto-deploy carries its
      # own snapshot mechanism for emergencies, so 7d is plenty.
      options = "--delete-older-than 7d";
    };
  };
  # Keep 5 boot generations across both bootloaders
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.grub.configurationLimit = 5;

  nixpkgs = {
    overlays = [
      outputs.overlays.additions
      outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
    };
  };
}
