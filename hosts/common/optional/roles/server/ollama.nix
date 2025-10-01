{ pkgs, config, lib, ... }: {

  options = {
    ollama.enable =
      lib.mkEnableOption "enables ollama server";
  };

  config = lib.mkIf config.ollama.enable {

    nixpkgs.overlays = [
      (self: super: {
        ollama-cuda = super.stdenv.mkDerivation rec {
          pname = "ollama";
          version = "0.12.0";

          src = super.fetchFromGitHub {
            owner = "ollama";
            repo = "ollama";
            rev = "v${version}";
            sha256 = "<fill-in-later>";
          };

          nativeBuildInputs = [ super.cmake super.gcc super.git super.pkgconfig ];

          buildInputs = [
            super.cudaPackages.cudatoolkit
            super.cudaPackages.cudnn
            super.zlib
            super.boost
            super.openblas
          ];

          cmakeFlags = [
            "-DCMAKE_BUILD_TYPE=Release"
            "-DCMAKE_CUDA_ARCHITECTURES=61" # 1080 Ti
          ];

          shellHook = ''
            export LD_LIBRARY_PATH=${super.cudaPackages.cudatoolkit}/lib64:${super.cudaPackages.cudnn}/lib:$LD_LIBRARY_PATH
          '';

          meta = with super.lib; {
            description = "Ollama LLM server compiled for CUDA 6.1";
            license = licenses.mit;
            platforms = platforms.linux;
          };
        };
      })
    ];

    services.ollama = {
      package = pkgs.callPackage pkgs.ollama-cuda {};  # point to the custom CUDA build
      enable = true;
      # handled in overlay
      # acceleration = "cuda";
      host = "0.0.0.0";
      port = 11434;
      environmentVariables = {
        # Ensure Ollama sees CUDA at runtime
        LD_LIBRARY_PATH = "${pkgs.cudaPackages.cudatoolkit}/lib64:${pkgs.cudaPackages.cudnn}/lib";
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
