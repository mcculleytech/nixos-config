{config, pkgs, lib, ...}: 
  { 

    imports = [
      ./workstation-user-options.nix
    ];
  
   sops.secrets.alex_hash = {
     sopsFile = ../../../../../secrets/main.yaml;
     neededForUsers = true;
   };

    users.mutableUsers = false;
    users.users.alex = {
      hashedPasswordFile = config.sops.secrets.alex_hash.path;
      isNormalUser = true;
      uid = 1000;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEZQ5hl6XP/iC45EnRpSQbxmAOKysPljVWFuXDleOWG alex@achilles"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF5/rm0SfHY4XP/yDT43MTPfCYmsoui53YvawXovlMDF alex@aeneas"
        "no-touch-required sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIBLAg2zXXAlqhi+wg1EaezH2TQW4rnQ0oULK6CnXyBS2AAAAD3NzaDpzeXN0ZW0tYXV0aA== YubiKey841-system-auth"
        "no-touch-required sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIP7VVX7OyA4eYm2nzJMmRl4EI8seJ3pTyUIuenTGivrcAAAAD3NzaDpzeXN0ZW0tYXV0aA== YubiKey840-system-auth"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEGkHcMirY9luPZudrCkXEL9EDnnrRGKPv8uEqChtdl alex@terminus"
      ];
      extraGroups = [ "wheel" "audio" "video" "plugdev" "dialout" "docker" "networkmanager" "adm" ];
    };

    # Need this currently for nixos-anywhere and remote builds. Would like to not do this.
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEZQ5hl6XP/iC45EnRpSQbxmAOKysPljVWFuXDleOWG alex@achilles"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF5/rm0SfHY4XP/yDT43MTPfCYmsoui53YvawXovlMDF alex@aeneas"
    ];

  }
