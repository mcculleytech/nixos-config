{ pkgs, ... }: 
{
  environment.systemPackages = [
      pkgs.arion
      pkgs.docker-client
  ];
  virtualisation.docker = {
      enable = true;
      storageDriver = "btrfs";
      rootless = {
	    enable = true;
	    setSocketVariable = true;
	  };
  };
  users.users.alex.extraGroups = [ "docker" ];
}
