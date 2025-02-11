# This uses a nifty trick to get the lastest service options for homepage-dashboard. Now I can fully declaritively configure it!
{ config, pkgs, inputs, lib, ... } @ args:
let
  tr_secrets = builtins.fromJSON (builtins.readFile ../../../../../secrets/git_crypt_traefik.json);
in
{

 	options = {
		homepage-dashboard.enable =
			lib.mkEnableOption "enables homepage-dashboard";
	};

	config = lib.mkIf config.homepage-dashboard.enable {
    ##############################
    #    Pulls from unstable     #
    ##############################
	   # imports = [
	   # 	"${args.inputs.nixpkgs-unstable}/nixos/modules/services/misc/homepage-dashboard.nix"
	   # ];
	   # disabledModules = [
    #   "services/misc/homepage-dashboard.nix"
    # 	];
    ##############################
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
	   	services = [
	   				{
              "Media" = [
                {
                  "Jellyfin" = {
                  	icon = "jellyfin.png";
                    href = "https://jellyfin.${tr_secrets.traefik.homelab_domain}";
                    description = "Home Media Server";
                  };
                }
                {
                  "Immich" = {
                    icon = "immich.png";
                    href = "https://immich.${tr_secrets.traefik.homelab_domain}";
                    description = "Photo Server";
                  };
                }
              ];
            }
            {
              "Services" = [
                {
                  "OpenWebUI" = {
                    icon = "https://api.openwebui.com/api/v1/models/017d6414-6bd3-46c8-9dfe-bcf6f23e6803/image";
                    href = "https://ai.${tr_secrets.traefik.homelab_domain}";
                    description = "Locally Hosted LLM";
                  };
                }
                {
                  "Octoprint" = {
                    icon = "octoprint.png";
                    href = "https://octoprint.${tr_secrets.traefik.homelab_domain}";
                    description = "3D Printer";
                  };
                }
                {
                  "Gitea" = {
                    icon = "gitea.png";
                    href = "https://source.${tr_secrets.traefik.homelab_domain}";
                    description = "Self Hosted Version Control";
                  };
                }
                {
                  "Radicale" = {
                    icon = "radicale.png";
                    href = "https://radicale.${tr_secrets.traefik.homelab_domain}/radicale";
                    description = "CardDAV and CalDAV server";
                  };
                }
                {
                  "Proton" = {
                    icon = "proton-mail.svg";
                    href = "https://proton.me";
                    description = "Privacy Respecting Email";
                  };
                }
              ];
            }
            {
              "Infrastructure" = [
                {
                  "Proxmox" = {
                  	icon = "proxmox.png";
                    href = "https://proxmox.${tr_secrets.traefik.homelab_domain}";
                    description = "Proxmox Hypervisor";
                  };
                }
                {
                   "Ludus" = {
                    icon = "https://ludus.cloud/opengraph-image.png";
                     href = "https://ludus.${tr_secrets.traefik.homelab_domain}";
                     description = "Ludus Cyber Range";
                   };
                 }
                {
                  "Tailscale" = {
                  	icon = "tailscale.png";
                    href = "https://tailscale.com";
                    description = "Wireguard Mesh Networking";
                  };
                }
                {
                  "Unifi Console" = {
                  	icon = "unifi.png";
                    href = "https://unifi.${tr_secrets.traefik.homelab_domain}";
                    description = "Unifi Router";
                  };
                 }
               {
                  "TrueNAS" = {
                  	icon = "truenas.png";
                    href = "https://truenas.${tr_secrets.traefik.homelab_domain}";
                    description = "Home NAS";
                  };
                }
                {
                   "Syncthing" = {
                    icon = "syncthing.png";
                     href = "https://syncthing.${tr_secrets.traefik.homelab_domain}";
                     description = "Syncthing Server";
                   };
                 }
                {
                   "Azure" = {
                    icon = "azure.png";
                     href = "https://portal.azure.com/#home";
                     description = "Azure Services";
                   };
                 }
                 {
                    "Traefik" = {
                     icon = "traefik.png";
                      href = "https://traefik.${tr_secrets.traefik.homelab_domain}/dashboard/";
                      description = "Traefik Reverse Proxy";
                    };
                  }
              ];
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
                { NixOS = [{ abbr = "NO"; href = "https://search.nixos.org/options"; }]; }
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
	};
}
