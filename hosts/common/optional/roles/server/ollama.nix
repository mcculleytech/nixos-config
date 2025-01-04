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
    
    environment.persistence = {
      "/persist" = {
      hideMounts = true;
        directories = [
          "/var/lib/private/ollama"
        ];
      };
    };
  };

}
