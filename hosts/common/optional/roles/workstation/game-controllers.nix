{pkgs, ... }: {
	environment.systemPackages = with pkgs; 
  	[
  		xboxdrv
  	];
}