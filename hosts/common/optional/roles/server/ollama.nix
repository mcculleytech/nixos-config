{ pkgs, config, lib, ... }: 
  # Have to add this for the 1080Ti since the arch is 6.1, nix doesn't have that in the prebuilt
# let
# custom-ollama-cuda = pkgs.ollama-cuda.overrideAttrs (old: rec {
#  buildPhase = ''
#     # Compute CUDA architectures manually for the build
#     cmake -B build \
#       -DCMAKE_SKIP_BUILD_RPATH=ON \
#       -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
#       -DCMAKE_CUDA_ARCHITECTURES=61 \
#
#      cmake --build build -j $NIX_BUILD_CORES
#   '';
#
#  });
# in
{

  options = {
    ollama.enable =
      lib.mkEnableOption "enables ollama server";
  };

  config = lib.mkIf config.ollama.enable {

    services.ollama = {
      package = pkgs.ollama-cuda.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          (pkgs.writeText "force-cuda-61.patch" ''
          --- a/ml/backend/ggml/ggml/CMakeLists.txt
          +++ b/ml/backend/ggml/ggml/CMakeLists.txt
          @@
          -cmakeFlagsCudaArchitectures = lib.optionalString enableCuda "-DCMAKE_CUDA_ARCHITECTURES='${cudaArchitectures}'";
          +cmakeFlagsCudaArchitectures = "-DCMAKE_CUDA_ARCHITECTURES=61";
          '')
    ];
  });
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
