{
  description = "NixOS and Home Manager flake";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/*";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    hardware.url = "github:nixos/nixos-hardware/master";
    sops-nix.url = "github:Mic92/sops-nix";
    impermanence.url = "github:nix-community/impermanence";
    # cosmic-nightly = {
    #   url = "github:busyboredom/cosmic-nightly-flake";
    #   inputs.nixpkgs.follows = "nixpkgs-unstable";
    # };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { self, nixpkgs, home-manager, hardware, ... } @ inputs:
    let
      inherit (self) outputs;

      defaultModules = [
        { nixpkgs.hostPlatform = "x86_64-linux"; }
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence
        inputs.sops-nix.nixosModules.sops
        inputs.determinate.nixosModules.default
      ];

      homeManagerServerModule = [
        home-manager.nixosModules.home-manager
        {
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs outputs; };
          home-manager.users.alex = {
            imports = [
              ./home/alex/server.nix
            ];
          };
          home-manager.backupFileExtension = "bak";
        }
      ];
    in
    rec {
      overlays = import ./overlays/unstable-pkgs.nix { inherit inputs; };

      devShells.x86_64-linux = let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in (import ./shells/bootstrap-shell.nix { inherit pkgs; }) // {
        c-maldev = import ./shells/c-maldev.nix { inherit pkgs; };
        go-dev = import ./shells/go-dev.nix { inherit pkgs; };
      };

      colmena = import ./colmena.nix { inherit inputs outputs defaultModules homeManagerServerModule; };

      # NixOS Configs
      nixosConfigurations = {
        # Framework 13 AMD Laptop
        "aeneas" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = defaultModules ++ [
            ./hosts/aeneas/configuration.nix
            hardware.nixosModules.framework-13-7040-amd
            # ({
            #   nixpkgs.overlays = [ inputs.cosmic-nightly.overlays.default ];
            # })
            home-manager.nixosModules.home-manager
            {
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs outputs; };
              home-manager.users.alex = {
                imports = [
                  ./home/alex/aeneas.nix
                ];
              };
              home-manager.backupFileExtension = "bak";
            }
          ];
        };

        # Dedicated GPU Server
        "saruman" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = defaultModules ++ [
            ./hosts/saruman/configuration.nix
            home-manager.nixosModules.home-manager
            hardware.nixosModules.common-gpu-nvidia-nonprime
            {
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs outputs; };
              home-manager.users.alex = {
                imports = [
                  ./home/alex/saruman.nix
                ];
              };
            }
          ];
        };

        # Testing Server
        "vader" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = defaultModules ++ homeManagerServerModule ++ [
            ./hosts/vader/configuration.nix
          ];
        };

        # Tailscale Subnet Router
        "phantom" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = defaultModules ++ homeManagerServerModule ++ [
            ./hosts/phantom/configuration.nix
          ];
        };

        # Blocky DNS Server
        "atreides" = nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = defaultModules ++ homeManagerServerModule ++ [
            ./hosts/atreides/configuration.nix
          ];
        };

      };

      # home-manager standalones - configure when needed
      # homeConfigurations = {
      #   "alex@achilles" = home-manager.lib.homeManagerConfiguration {
      #     pkgs = nixpkgs.legacyPackages.x86_64-linux;
      #     extraSpecialArgs = { inherit inputs outputs; };
      #     modules = [ ./home/alex/achilles.nix ];
      #   };
      # };
    };
}
