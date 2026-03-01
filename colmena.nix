{ inputs, outputs, defaultModules, homeManagerServerModule }:

{
  meta = {
    nixpkgs = import inputs.nixpkgs { system = "x86_64-linux"; };
    specialArgs = { inherit inputs outputs; };
  };

  saruman = {
    deployment = {
      targetHost = "saruman";
      targetUser = "alex";
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
      targetHost = "vader";
      targetUser = "alex";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/vader/configuration.nix
    ];
  };

  phantom = {
    deployment = {
      targetHost = "phantom";
      targetUser = "alex";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/phantom/configuration.nix
    ];
  };

  atreides = {
    deployment = {
      targetHost = "atreides";
      targetUser = "alex";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/atreides/configuration.nix
    ];
  };

  maul = {
    deployment = {
      targetHost = "maul";
      targetUser = "alex";
      tags = [ "server" ];
    };
    imports = defaultModules ++ homeManagerServerModule ++ [
      ./hosts/maul/configuration.nix
    ];
  };
}
