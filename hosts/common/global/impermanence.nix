{ lib, inputs, config, ... }: {
  # Taken from Misterio77's config

  environment.persistence = {
    "/persist" = {
    hideMounts = true;
      directories = [
        "/var/lib/systemd"
        "/var/lib/NetworkManager"
        "/var/lib/nixos"
        "/var/lib/tailscale"
        "/var/log"
        "/etc/NetworkManager"
      ];
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