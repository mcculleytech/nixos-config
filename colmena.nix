{ inputs, outputs, defaultModules, homeManagerServerModule }:
let
  hostData = import ./hosts/common/hosts-data.nix;
in
{
  meta = {
    nixpkgs = import inputs.nixpkgs { localSystem = "x86_64-linux"; };
    specialArgs = { inherit inputs outputs; };
  };

  saruman = {
    deployment = {
      targetHost = hostData.saruman.ip;
      targetUser = "root";
      allowLocalDeployment = true;
      tags = [ "server" "gpu" ];
    };
    imports = defaultModules ++ [
      inputs.hardware.nixosModules.common-gpu-nvidia-nonprime
      inputs.home-manager.nixosModules.home-manager
      ./hosts/saruman/configuration.nix
      {
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit inputs outputs; };
        home-manager.users.alex.imports = [ ./home/alex/saruman.nix ];
        home-manager.backupFileExtension = "bak";
      }
    ];
  };

  vader = {
    deployment = {
      targetHost = hostData.vader.ip;
      targetUser = "root";
      tags = [ "server" "vm" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/vader/configuration.nix
    ];
  };

  phantom = {
    deployment = {
      targetHost = hostData.phantom.ip;
      targetUser = "root";
      tags = [ "server" "vm" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/phantom/configuration.nix
    ];
  };

  atreides = {
    deployment = {
      targetHost = hostData.atreides.ip;
      targetUser = "root";
      tags = [ "server" "vm" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/atreides/configuration.nix
    ];
  };

  aeneas = {
    deployment = {
      targetHost = "aeneas";
      targetUser = "root";
      tags = [ "workstation" ];
    };
    imports = defaultModules ++ [
      inputs.hardware.nixosModules.framework-13-7040-amd
      inputs.home-manager.nixosModules.home-manager
      ./hosts/aeneas/configuration.nix
      {
        home-manager.useUserPackages = true;
        home-manager.extraSpecialArgs = { inherit inputs outputs; };
        home-manager.users.alex.imports = [
          ./home/alex/aeneas.nix
        ];
        home-manager.backupFileExtension = "bak";
      }
    ];
  };
}
