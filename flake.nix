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
    claude-code = {
      url = "github:sadjow/claude-code-nix";
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

      hostData = import ./hosts/common/hosts-data.nix;

      # Single host definition map — both nixosConfigurations and colmena are
      # generated from this, so there is only one place to add or change a host.
      hostDefs = {
        # Framework 13 AMD Laptop
        aeneas = {
          modules = defaultModules ++ [
            hardware.nixosModules.framework-13-7040-amd
            home-manager.nixosModules.home-manager
            ./hosts/aeneas/configuration.nix
            {
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs outputs; };
              home-manager.users.alex.imports = [ ./home/alex/aeneas.nix ];
              home-manager.backupFileExtension = "bak";
            }
          ];
          deployment = {
            targetHost = "aeneas";
            targetUser = "root";
            tags = [ "workstation" ];
          };
        };

        # Dedicated GPU Server
        saruman = {
          modules = defaultModules ++ [
            hardware.nixosModules.common-gpu-nvidia-nonprime
            home-manager.nixosModules.home-manager
            ./hosts/saruman/configuration.nix
            {
              home-manager.useUserPackages = true;
              home-manager.extraSpecialArgs = { inherit inputs outputs; };
              home-manager.users.alex.imports = [ ./home/alex/saruman.nix ];
              home-manager.backupFileExtension = "bak";
            }
          ];
          deployment = {
            targetHost = hostData.saruman.ip;
            targetUser = "root";
            allowLocalDeployment = true;
            tags = [ "server" "gpu" ];
          };
        };

        # Testing Server
        vader = {
          modules = defaultModules ++ homeManagerServerModule ++ [
            ./hosts/vader/configuration.nix
          ];
          deployment = {
            targetHost = hostData.vader.ip;
            targetUser = "root";
            tags = [ "server" "vm" ];
          };
        };

        # Tailscale Subnet Router
        phantom = {
          modules = defaultModules ++ homeManagerServerModule ++ [
            ./hosts/phantom/configuration.nix
          ];
          deployment = {
            targetHost = hostData.phantom.ip;
            targetUser = "root";
            tags = [ "server" "vm" ];
          };
        };

        # Blocky DNS Server
        atreides = {
          modules = defaultModules ++ homeManagerServerModule ++ [
            ./hosts/atreides/configuration.nix
          ];
          deployment = {
            targetHost = hostData.atreides.ip;
            targetUser = "root";
            tags = [ "server" "vm" ];
          };
        };
      };
    in
    rec {
      overlays = import ./overlays/unstable-pkgs.nix { inherit inputs; };

      devShells.x86_64-linux = let
        pkgs = nixpkgs.legacyPackages.x86_64-linux;
      in (import ./shells/bootstrap-shell.nix { inherit pkgs; }) // {
        c-maldev = import ./shells/c-maldev.nix { inherit pkgs; };
        go-dev = import ./shells/go-dev.nix { inherit pkgs; };
      };

      colmena = import ./colmena.nix { inherit inputs outputs hostDefs; };

      nixosConfigurations = builtins.mapAttrs (name: def:
        nixpkgs.lib.nixosSystem {
          specialArgs = { inherit inputs outputs; };
          modules = def.modules;
        }
      ) hostDefs;
    };
}
