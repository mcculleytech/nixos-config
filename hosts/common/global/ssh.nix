{
  services.openssh = {
    enable = true;
    settings = {
      PermitRootLogin = "no";
      PasswordAuthentication = false;
    };
  };
  users.users."alex".openssh.authorizedKeys.keys = [
    "sk-ssh-ed25519@openssh.com AAAAGnNrLXNzaC1lZDI1NTE5QG9wZW5zc2guY29tAAAAIBLAg2zXXAlqhi+wg1EaezH2TQW4rnQ0oULK6CnXyBS2AAAAD3NzaDpzeXN0ZW0tYXV0aA== ssh:system-auth"
  ];
}
