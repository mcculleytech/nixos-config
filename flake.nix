{
  description = "NixOS and Home Manager flake";

  inputs = {
    nixpkgs.url = "https://flakehub.com/f/NixOS/nixpkgs/0";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    determinate.url = "https://flakehub.com/f/DeterminateSystems/determinate/*";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    hardware.url = "github:nixos/nixos-hardware/master";
    sops-nix.url = "github:Mic92/sops-nix";    
    impermanence.url = "github:nix-community/impermanence";
    cosmic-nightly = {
      url = "github:busyboredom/cosmic-nightly-flake";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-25.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs-unstable";
    };
  };

  outputs = { 
    self, 
    nixpkgs,
    home-manager,
    hardware,
     ...
  } @ inputs:
    let
      inherit (self) outputs;

      defaultModules = [
        inputs.disko.nixosModules.disko
        inputs.impermanence.nixosModules.impermanence
        inputs.sops-nix.nixosModules.sops
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
    overlays = import ./overlays/unstable-pkgs.nix { inherit inputs ; };
    # NixOS Configs
    nixosConfigurations = {
      # Framework 13 AMD Laptop
      "aeneas" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
        modules = defaultModules ++ [
          ./hosts/aeneas/configuration.nix
          hardware.nixosModules.framework-13-7040-amd
          ({
            nixpkgs.overlays = [ inputs.cosmic-nightly.overlays.default ];
          })
          inputs.determinate.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              imports = [
              ./home/alex/aeneas.nix
              inputs.nixvim.homeModules.nixvim
              ];
            };
            home-manager.backupFileExtension = "bak";
          }
        ];
      };

      # Main Custom Desktop 
      "achilles" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
	      modules = defaultModules ++ [
	        ./hosts/achilles/configuration.nix
          #hardware.nixosModules.common-gpu-nvidia-nonprime
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              imports = [
              ./home/alex/achilles.nix
              inputs.nixvim.homeModules.nixvim
              ];
            };
            home-manager.backupFileExtension = "bak";
          }
	      ];
      };

      # Dedicated GPU Server 
      "saruman" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
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
        system = "x86_64-linux";
        modules = defaultModules ++ homeManagerServerModule ++ [
          ./hosts/vader/configuration.nix
        ];
      };

      # Tailscale Subnet Router
      "phantom" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
        modules = defaultModules ++ homeManagerServerModule ++ [
          ./hosts/phantom/configuration.nix
        ];
      };

      # Blocky DNS Server
      "atreides" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
        modules = defaultModules ++ homeManagerServerModule ++ [
          ./hosts/atreides/configuration.nix
        ];
      };

      # Backup Server
      "maul" = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        system = "x86_64-linux";
        modules = defaultModules ++ homeManagerServerModule ++ [
          ./hosts/maul/configuration.nix
        ];
      };

    };

    # home-manager standalones - configure when needed
    # homeConfigurations = {
    #   "alex@achilles" = home-manager.lib.homeManagerConfiguration {
	  #      pkgs = nixpkgs.legacyPackages.x86_64-linux;
	  #      extraSpecialArgs = { inherit inputs outputs; };
	  #      modules = [ ./home/alex/achilles.nix ];
    #   };
    # };
  };
}
