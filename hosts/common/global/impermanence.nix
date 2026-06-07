{ lib, inputs, config, pkgs, ... }: {
  # Taken from Misterio77's config

  environment.persistence = {
    "/persist" = {
    hideMounts = true;
      directories = [
        "/var/lib/systemd"
        "/var/lib/NetworkManager"
        "/var/lib/bluetooth"
        "/var/lib/nixos"
        "/var/lib/sops-nix"
        { directory = "/var/lib/libvirt"; user = "root"; group = "root"; }
        "/var/log"
        "/etc/NetworkManager"
      ] ++ (lib.optionals config.services.postgresql.enable [
        "/var/lib/postgresql"
      ]);
      files = [
        "/etc/machine-id"
        "/etc/ssh/ssh_host_ed25519_key"
        "/etc/ssh/ssh_host_ed25519_key.pub"
        "/etc/ssh/ssh_host_rsa_key"
        "/etc/ssh/ssh_host_rsa_key.pub"
      ];
    };
  };
  programs.fuse.userAllowOther = true;

  # systemd ≥256 refuses to set up a DynamicUser StateDirectory if
  # /var/lib/private is more permissive than 0700 ("Directory /var/lib/private
  # ... has mode 0755 that is too permissive (0700 was requested), refusing"
  # → status=238/STATE_DIRECTORY). Under impermanence /var/lib/private is
  # created as the mount-point parent for the per-service persisted state dirs
  # (var-lib-private-*.mount) at 0755, and the per-service
  # `d /var/lib/private 0700` tmpfiles rules don't reliably override it across
  # the mount boundary. A systemd bump (flake.lock update, 2026-06-07) made
  # the check strict and silently broke every DynamicUser service on atreides
  # (otelcol, ntfy, alertmanager, alloy, tempo, …) on next restart. Force the
  # mode in early boot — after the bind mounts land, before any service
  # starts. No-op where /var/lib/private doesn't exist.
  systemd.services.fix-var-lib-private-perms = {
    description = "Force /var/lib/private to 0700 (systemd DynamicUser requirement)";
    wantedBy = [ "sysinit.target" ];
    before = [ "sysinit.target" ];
    after = [ "local-fs.target" ];
    unitConfig = {
      ConditionPathExists = "/var/lib/private";
      DefaultDependencies = false;
    };
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.coreutils}/bin/chmod 0700 /var/lib/private";
    };
  };

  security.sudo.extraConfig = ''
    # rollback results in sudo lectures after each reboot
    Defaults lecture = never
  '';

  # This is technically unneeded if not opting in for home impermanence. It creates unnecessary dirs in the /persist subvol but I'm ok with that.
  system.activationScripts.persistent-dirs.text =
    let
      mkHomePersist = user: lib.optionalString user.createHome ''
        mkdir -p /persist/${user.home}
        chown ${user.name}:${user.group} /persist/${user.home}
        chmod ${user.homeMode} /persist/${user.home}
      '';
      users = lib.attrValues config.users.users;
    in
    lib.concatLines (map mkHomePersist users);
}