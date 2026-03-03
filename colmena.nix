{ inputs, outputs, defaultModules, homeManagerServerModule }:

let
  platformModule = { nixpkgs.hostPlatform = "x86_64-linux"; };
in
{
  meta = {
    nixpkgs = import inputs.nixpkgs { localSystem = "x86_64-linux"; };
    specialArgs = { inherit inputs outputs; };
  };

  saruman = {
    deployment = {
      targetHost = "saruman";
      targetUser = "root";
      allowLocalDeployment = true;
      tags = [ "server" "gpu" ];
    };
    imports = defaultModules ++ [
      platformModule
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
      targetHost = "vader";
      targetUser = "root";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      platformModule
      ./hosts/vader/configuration.nix
    ];
  };

  phantom = {
    deployment = {
      targetHost = "phantom";
      targetUser = "root";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      platformModule
      ./hosts/phantom/configuration.nix
    ];
  };

  atreides = {
    deployment = {
      targetHost = "atreides";
      targetUser = "root";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      platformModule
      ./hosts/atreides/configuration.nix
    ];
  };

  maul = {
    deployment = {
      targetHost = "maul";
      targetUser = "root";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      platformModule
      ./hosts/maul/configuration.nix
    ];
  };
}
