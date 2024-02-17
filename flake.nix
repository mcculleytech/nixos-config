{
  description = "Workstation NixOS and Home Manager flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-23.11";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-23.11";
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
    hardware,
    nix-colors,
    sops-nix,
    impermanence,
    disko,
     ...
  }@inputs:
    let
      inherit (self) outputs;
    in
    rec {
    overlays = import ./overlays/unstable-pkgs.nix { inherit inputs ; };
    # NixOS Configs
    nixosConfigurations = {
      # Dell XPS 15 Laptop
      "aeneas" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/aeneas/configuration.nix
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
          hardware.nixosModules.dell-xps-15-9500#-nvidia
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              (impermanence + "/home-manager.nix")
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
	      modules = [
	        ./hosts/achilles/configuration.nix
          disko.nixosModules.disko
          impermanence.nixosModules.impermanence
	        hardware.nixosModules.common-gpu-nvidia-nonprime
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              #(impermanence + "/home-manager.nix")
              ./home/alex/achilles.nix
              ];
            };
          }
	      ];
      };

      # Testing Server
      "vader" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        system = "x86_64-linux";
        modules = [
          disko.nixosModules.disko
          sops-nix.nixosModules.sops
          ./hosts/vader/configuration.nix
          impermanence.nixosModules.impermanence
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              (impermanence + "/home-manager.nix")
              ./home/alex/vader.nix
              ];
            };
          }
        ];
      };

      # Backup Server
      "maul" = nixpkgs.lib.nixosSystem {
        specialArgs = {inherit inputs outputs;};
        modules = [
          ./hosts/maul/configuration.nix
          sops-nix.nixosModules.sops
          home-manager.nixosModules.home-manager
          {
            home-manager.useGlobalPkgs = true;
            home-manager.useUserPackages = true;
            home-manager.users.alex = import ./home/alex/maul.nix;
          }
        ];
      };

    };

    # home-manager
    homeConfigurations = {
      "alex@achilles" = home-manager.lib.homeManagerConfiguration {
	       pkgs = nixpkgs.legacyPackages.x86_64-linux;
	       extraSpecialArgs = { inherit inputs outputs; };
	       modules = [ ./home/alex/achilles.nix ];
      };
    };
  };
}
