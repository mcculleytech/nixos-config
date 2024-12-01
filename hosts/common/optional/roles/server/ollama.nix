{ pkgs, config, lib, ... }: {

  options = {
		ollama.enable =
			lib.mkEnableOption "enables ollama server";
	};

	config = lib.mkIf config.ollama.enable {
    services.ollama = {
      package = pkgs.unstable.ollama;
      enable = true;
      acceleration = "cuda";
      host = "0.0.0.0";
      port = 11434;
    };

    # Have to use docker for open-webui. Hopefully this will get packaged in the future.
    virtualisation.oci-containers.backend = "docker";
    virtualisation.oci-containers.containers.open-webui = {
        autoStart = true;
        image = "ghcr.io/open-webui/open-webui";
        ports = [ "3000:8080" ];
        # TODO figure out how to create the data directory declaratively
        volumes = [ "${config.users.users.alex.home}/LLM/open-webui:/app/backend/data" ];
        extraOptions =
          [ "--network=host" "--add-host=host.containers.internal:host-gateway" ];
        environment = {
          OLLAMA_API_BASE_URL = "http://localhost:11434/api";
        };
      };

    environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
          "/var/lib/private"
        ];
      };
    };

    networking.firewall.allowedTCPPorts = [ 11434 8080 3000 ];

    # This is needed for Nvidia to work after suspend with ollama
    # boot.extraModprobeConfig = ''
    #   options nvidia NVreg_PreserveVideoMemoryAllocations=1 NVreg_TemporaryFilePath=/tmp
    # '';
	};

}
