# This file defines overlays
{ inputs, ... }:
{
  # This one brings our custom packages from the 'pkgs' directory
  additions = final: _prev: import ../pkgs { pkgs = final; };

  # This one contains whatever you want to overlay
  # You can change versions, add patches, set compilation flags, anything really.
  # https://nixos.wiki/wiki/Overlays
  modifications = final: prev: {
    # example = prev.example.overrideAttrs (oldAttrs: rec {
    # ...
    # });
  };

  # When applied, the unstable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.unstable'
  unstable-packages = final: _prev: {
    unstable = import inputs.nixpkgs-unstable {
      localSystem = final.stdenv.hostPlatform.system;
      config = {
        allowUnfree = true;
        permittedInsecurePackages = [
          "openssl-1.1.1w"
          "electron-25.9.0"
        ];
      };
      overlays = [
        (ufinal: uprev:
          let
            ollamaVersionOverride = old: {
              version = "0.20.2";
              src = uprev.fetchFromGitHub {
                owner = "ollama";
                repo = "ollama";
                tag = "v0.20.2";
                hash = "sha256-Ic3eLOohLR7MQGkLvDJBNOCiBBKxh6l8X9MgK0b4w+Y=";
              };
              vendorHash = "sha256-Lc1Ktdqtv2VhJQssk8K1UOimeEjVNvDWePE9WkamCos=";
            };
          in {
            ollama = uprev.ollama.overrideAttrs ollamaVersionOverride;
            ollama-cuda = uprev.ollama-cuda.overrideAttrs ollamaVersionOverride;
          })
      ];
    };
  };


}
