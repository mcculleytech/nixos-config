{ pkgs, config, lib, ... }: {

  options = {
    security-tooling.enable = lib.mkEnableOption "enables security tooling packages";
  };

  config = lib.mkIf config.security-tooling.enable {
    home.packages = with pkgs; [
      unstable.hashcat
      unstable.metasploit
      unstable.burpsuite
    ];
  };
}
