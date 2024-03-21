{ config, ...}: {

	sops.secrets = {
	  cloudflare_email = {
	    sopsFile = ../../../../atreides/secrets.yaml;
	  };
	  cloudflare_api_key = {
	    sopsFile = ../../../../atreides/secrets.yaml;
	  };
	};
	networking.firewall.allowedTCPPorts = [ 80 443 ];

	security.acme = {
		acceptTerms = true;
		defaults = {
			email = "alex@mcculley.tech";
			dnsProvider = "cloudflare";
			credentialFiles = {
				CLOUDFLARE_EMAIL_FILE = config.sops.secrets.cloudflare_email.path;
				CLOUDFLARE_API_KEY_FILE = config.sops.secrets.cloudflare_api_key.path;
			};
		};
		certs = {
			"test.chonkywolf.live" = {
			  inheritDefaults = true;
			  domain = "*.test.chonkywolf.live";
			  extraDomainNames = ["test.chonkywolf.live"];
			};
		};
	};

	environment.persistence = {
    "/persist" = {
    hideMounts = true;
      directories = [
        "/var/lib/acme"
      ];
    };
  };
}