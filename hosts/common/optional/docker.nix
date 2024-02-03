{
  virtualisation.docker = {
      enable = true;
      storageDriver = "btrfs";
      rootless = {
	    enable = true;
	    setSocketVariable = true;
	  };
  };
  users.users.alex.extraGroups = [ "docker" ];
  modules = [ arion.nixosModules.arion ];
}
