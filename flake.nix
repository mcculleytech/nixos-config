{
  description = "NixOS and Home Manager flake";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-25.05";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    home-manager.url = "github:nix-community/home-manager/release-25.05";
    hyprland.url = "git+https://github.com/hyprwm/Hyprland?submodules=1";
    home-manager.inputs.nixpkgs.follows = "nixpkgs";
    hardware.url = "github:nixos/nixos-hardware/master";
    nix-colors.url = "github:misterio77/nix-colors";
    sops-nix.url = "github:Mic92/sops-nix";    
    impermanence.url = "github:nix-community/impermanence";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs-unstable";
    nixos-cosmic = {
      url = "github:lilyinstarlight/nixos-cosmic";
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
    hyprland, 
    hardware,
    nix-colors,
    sops-nix,
    impermanence,
    disko,
    nixos-cosmic,
    nixvim,
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
            ./home/alex/server.nix
            (impermanence + "/home-manager.nix")
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
        modules = defaultModules ++ [
          ./hosts/aeneas/configuration.nix
          {
            nix.settings = {
              substituters = [ "https://cosmic.cachix.org/" ];
              trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=" ];
            };
          }
          hardware.nixosModules.framework-13-7040-amd
          nixos-cosmic.nixosModules.default
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              # (impermanence + "/home-manager.nix")
              ./home/alex/aeneas.nix
              nixvim.homeManagerModules.nixvim
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
          nixos-cosmic.nixosModules.default
	        ./hosts/achilles/configuration.nix
          {
            nix.settings = {
              substituters = [ "https://cosmic.cachix.org/" ];
              trusted-public-keys = [ "cosmic.cachix.org-1:Dya9IyXD4xdBehWjrkPv6rtxpmMdRel02smYzA85dPE=" ];
            };
          }
          #hardware.nixosModules.common-gpu-nvidia-nonprime
          home-manager.nixosModules.home-manager
          {
            home-manager.useUserPackages = true;
            home-manager.extraSpecialArgs = { inherit inputs outputs; };
            home-manager.users.alex = {
              # Import impermanence to home-manager
              imports = [
              # (impermanence + "/home-manager.nix")
              ./home/alex/achilles.nix
              nixvim.homeManagerModules.nixvim
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
              # Import impermanence to home-manager
              imports = [
              # (impermanence + "/home-manager.nix")
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
