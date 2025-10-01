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
      environmentVariables = {
        PATH = "${pkgs.cudatoolkit}/bin:${pkgs.cudaPackages.cudnn}/bin:${pkgs.cudnn_cudatoolkit}/bin:${pkgs.cudaPackages.libcublas}/bin:$PATH";
        LD_LIBRARY_PATH = "${pkgs.cudatoolkit}/lib:${pkgs.cudaPackages.cudnn}/lib:${pkgs.cudaPackages.libcublas}/lib:$LD_LIBRARY_PATH";
        NVIDIA_VISIBLE_DEVICES = "all";
        NVIDIA_DRIVER_CAPABILITIES = "compute,utility";
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
