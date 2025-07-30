{pkgs, ... }: {
	environment.systemPackages = with pkgs; 
  	[
  		antimicrox
  	];
}