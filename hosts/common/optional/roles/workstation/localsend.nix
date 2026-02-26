{ pkgs, config, lib, inputs, ... }:
{

  options = {
    localsend.enable = lib.mkEnableOption "enables localsend. Airdrop replacement for desktop and mobile.";
  };


  config = lib.mkIf config.localsend.enable {

    programs.localsend ={
      enable = true;
      openFirewall = true;
    };

  };

}
