# This uses a nifty trick to get the lastest service options for homepage-dashboard. Now I can fully declaritively configure it!
{ config, pkgs, inputs, ... } @ args:
let
 hp_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_homepage.json);
in
{
	imports = [
		"${args.inputs.nixpkgs-unstable}/nixos/modules/services/misc/homepage-dashboard.nix"
	];
	disabledModules = [
    "services/misc/homepage-dashboard.nix"
  	];


	services.homepage-dashboard ={
		package = pkgs.unstable.homepage-dashboard;
		# default port is 8082
		openFirewall = true;
		enable = true;
		widgets = [
			  {
			    resources = {
			      cpu = true;
			      disk = "/";
			      memory = true;
			    };
			  }
			  {
			    search = {
			      provider = "google";
			      target = "_blank";
			    };
			  }
		];
		settings = {
			logpath = "/var/log/homepage-dashboard";
		};
		bookmarks = [
			{
            Productivity = [
              { Github = [{ abbr = "GH"; href = "https://github.com/"; }]; }
              { Blog = [{ abbr = "MT"; href = "https://blog.mcculley.tech/"; }]; }
            ];
          	}
          	{
            Entertainment = [
              { YouTube = [{ abbr = "YT"; href = "https://youtube.com/"; }]; }
            ];
          	}
          	{
            CTFs = [
              { TryHackMe = [{ abbr = "THM"; href = "https://tryhackme.com/"; }]; }
              { HackTheBox = [{ abbr = "HTB"; href = "https://hackthebox.com/"; }]; }
            ];
          	}
        ];
    };
}