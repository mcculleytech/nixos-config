{ pkgs, config, lib, ... }: {

  options = {
    ollama.enable =
      lib.mkEnableOption "enables ollama server";
  };

  config = lib.mkIf config.ollama.enable {

    services.ollama = {
      package = pkgs.unstable.ollama-cuda.override {
        cudaArches = [ "61" ];
      };
      enable = true;
      acceleration = "cuda";
      host = "0.0.0.0";
      port = 11434;
      environmentVariables = {

      };
    };
    
    # DynamicUser requires /var/lib/private with mode 0700
    systemd.tmpfiles.rules = [
      "d /var/lib/private 0700 root root -"
    ];

    environment.persistence = {
      "/persist" = {
        hideMounts = true;
        directories = [
          { directory = "/var/lib/private/ollama"; user = "root"; group = "root"; mode = "0700"; }
        ];
      };
    };
  };

}
