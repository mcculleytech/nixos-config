{
  description = "NixOS and Home Manager flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-24.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-24.05";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hardware.url = "github:nixos/nixos-hardware/master";
    nix-colors.url = "github:misterio77/nix-colors";
    sops-nix.url = "github:Mic92/sops-nix";
    impermanence.url = "github:nix-community/impermanence";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";
  };

  outputs = { 
    self, 
    nixpkgs,
    home-manager,
    hyprland, 
    hardware,
    nix-colors,
    sops-nix,
    impermanence,
    disko,
     ...
  }@inputs:
    let
      inherit (self) outputs;

      defaultModules = [
        disko.nixosModules.disko
        impermanence.nixosModules.impermanence
        sops-nix.nixosModules.sops
      ];

      homeManagerServerModule = [
      home-manager.nixosModules.home-manager
        {
          home-manager.useUserPackages = true;
          home-manager.extraSpecialArgs = { inherit inputs outputs; };
          home-manager.users.alex = {
            # Import impermanence to home-manager
            imports = [
            (impermanence + "/home-manager.nix")
            ./home/alex/server.nix
            ];
          };
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
        modules = defaultModules ++ [
          ./hosts/aeneas/configuration.nix
          hardware.nixosModules.framework-13-7040-amd
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              # (impermanence + "/home-manager.nix")
              ./home/alex/aeneas.nix
              ];
            };
          }
        ];
      };

      # Main Custom Desktop 
      "achilles" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
	      modules = defaultModules ++ [
	        ./hosts/achilles/configuration.nix
          home-manager.nixosModules.home-manager
	        hardware.nixosModules.common-gpu-nvidia-nonprime
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              # (impermanence + "/home-manager.nix")
              ./home/alex/achilles.nix
              ];
            };
          }
	      ];
      };

      # Garage PC
      "jak" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
        modules = defaultModules ++ [
          ./hosts/jak/configuration.nix
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              # (impermanence + "/home-manager.nix")
              ./home/alex/jak.nix
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
