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

  environment.persistence = {
    "/persist" = {
    hideMounts = true;
      directories = [
        "/var/lib/docker"
      ];
    };
  };

  users.users.alex.extraGroups = [ "docker" ];
}
