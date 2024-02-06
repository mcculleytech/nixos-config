{ config, pkgs, ... }:
{
	services.gitea = {
		enable = true;
		settings = {
			service = {
				DISABLE_REGISTRATION = true;
			};
			indexer = {
          		REPO_INDEXER_ENABLED = true;
        	};
			server = {
				PROTOCOL = "https";
				DOMAIN = "source.mcculley.tech";
				ROOT_URL = "https://source.mcculley.tech";
				HTTP_PORT = 9001;
			};
		};
		appName = "McCulley Tech Gitea ";
		database = { 
			type = "postgres";
		};
	};
}