{ pkgs, config, lib, ... }: 
  # Have to add this for the 1080Ti since the arch is 6.1, nix doesn't have that in the prebuilt
  let
    custom-ollama-cuda = pkgs.ollama-cuda.overrideAttrs (old: {
      cmakeFlags = (old.cmakeFlags or []) ++ [ "-DCMAKE_CUDA_ARCHITECTURES=61" ];
    });
  in
{

  options = {
    ollama.enable =
      lib.mkEnableOption "enables ollama server";
  };

  config = lib.mkIf config.ollama.enable {

    services.ollama = {
      package = custom-ollama-cuda;
      enable = true;
      acceleration = "cuda";
      host = "0.0.0.0";
      port = 11434;
      environmentVariables = {

      };
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
