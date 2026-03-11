{ inputs, outputs, defaultModules, homeManagerServerModule }:

{
  meta = {
    nixpkgs = import inputs.nixpkgs { localSystem = "x86_64-linux"; };
    specialArgs = { inherit inputs outputs; };
  };

  saruman = {
    deployment = {
      targetHost = "10.1.8.6";
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
      targetHost = "10.2.1.245";
      targetUser = "root";
      tags = [ "server" "vm" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/vader/configuration.nix
    ];
  };

  phantom = {
    deployment = {
      targetHost = "10.1.8.121";
      targetUser = "root";
      tags = [ "server" "vm" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/phantom/configuration.nix
    ];
  };

  atreides = {
    deployment = {
      targetHost = "10.1.8.129";
      targetUser = "root";
      tags = [ "server" "vm" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
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
      ./hosts/maul/configuration.nix
    ];
  };
}
