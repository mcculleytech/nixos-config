{ inputs, lib, config, pkgs, outputs, ... }: {

    imports = [
      ./global
      ./optional/desktop-packages.nix
      ./optional/terminator.nix
      ./optional/zsh.nix
    ];

  nixpkgs = {
    overlays = [
    outputs.overlays.unstable-packages
    ];
    config = {
      allowUnfree = true;
      allowUnfreePredicate = (_: true);
    };
  };

}