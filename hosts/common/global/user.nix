{config, pkgs, lib, ...}: 

  let 
    workstations = [ 
      "achilles" 
      "aeneas" 
    ];
    servers = [ 
      "maul" 
      "vader" 
    ];

    checkHostname = hostname: hostnameList: 
      lib.elem hostname hostnameList;
  in
  { 
  
    sops.secrets.alex_hash = {
      sopsFile = ../../../secrets/main.yaml;
      neededForUsers = true;
    };

    programs.zsh.enable = true;
    users.mutableUsers = false;
    users.users.alex = {
      hashedPasswordFile = config.sops.secrets.alex_hash.path;
      isNormalUser = true;
      openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEZQ5hl6XP/iC45EnRpSQbxmAOKysPljVWFuXDleOWG alex@achilles"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqyTO3X8pqfIE+24+vtjlGi3FocJwDFzSkuhYQlzSUl alex@aeneas"
        "no-touch-required sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIBLAg2zXXAlqhi+wg1EaezH2TQW4rnQ0oULK6CnXyBS2AAAAD3NzaDpzeXN0ZW0tYXV0aA== YubiKey841-system-auth"
        "no-touch-required sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIP7VVX7OyA4eYm2nzJMmRl4EI8seJ3pTyUIuenTGivrcAAAAD3NzaDpzeXN0ZW0tYXV0aA== YubiKey840-system-auth"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEGkHcMirY9luPZudrCkXEL9EDnnrRGKPv8uEqChtdl alex@terminus"
      ];
      shell = if checkHostname "${config.networking.hostName}" workstations then pkgs.zsh else pkgs.bash;
      extraGroups = [ "wheel" "libvirtd" "audio" "plugdev" "dialout" ];
    };

    # Need this currently for nixos-anywhere and remote builds. Would like to not do this.
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAEZQ5hl6XP/iC45EnRpSQbxmAOKysPljVWFuXDleOWG alex@achilles"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAICqyTO3X8pqfIE+24+vtjlGi3FocJwDFzSkuhYQlzSUl alex@aeneas"
    ];

  }
