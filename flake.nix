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
  };

  outputs = { 
    self, 
    nixpkgs, 
    home-manager, 
    hardware,
    nix-colors,
    sops-nix,
    impermanence,
     ...
  }@inputs:
    let
      inherit (self) outputs;
    in
    rec {
    overlays = import ./overlays/unstable-pkgs.nix { inherit inputs; };
    # NixOS Configs
    nixosConfigurations = {
      "aeneas" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
        modules = [
          ./hosts/aeneas/configuration.nix
          hardware.nixosModules.dell-xps-15-9500#-nvidia
        ];
      };

      "achilles" = nixpkgs.lib.nixosSystem {
        specialArgs = { inherit inputs outputs; };
	       modules = [
	         ./hosts/achilles/configuration.nix
	         hardware.nixosModules.common-gpu-nvidia-nonprime
	      ];
      };
    };

    # home-manager
    homeConfigurations = {
      "alex@aeneas" = home-manager.lib.homeManagerConfiguration {
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
        extraSpecialArgs = { inherit inputs outputs; };
        modules = [ ./home/alex/aeneas.nix ];
      };
      
      "alex@achilles" = home-manager.lib.homeManagerConfiguration {
	     pkgs = nixpkgs.legacyPackages.x86_64-linux;
	     extraSpecialArgs = { inherit inputs outputs; };
	     modules = [ ./home/alex/achilles.nix ];
      };
    };
  };
}
