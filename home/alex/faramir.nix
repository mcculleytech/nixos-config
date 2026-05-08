{ pkgs, ... }:
{
  imports = [
    ./global
    ./optional/zsh.nix
  ];

  nixpkgs.overlays = [
    # direnv 2.37.1's `make test-fish` gets SIGKILLed in the build sandbox on
    # Apple Silicon. Skip the test suite — direnv itself works fine.
    (final: prev: {
      direnv = prev.direnv.overrideAttrs (_: { doCheck = false; });
    })
  ];

  zsh.enable = true;

  home.packages = with pkgs; [
    direnv
    starship
    fzf
    htop
    tmux
    jq
    yq
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship.enable = true;
  programs.fzf.enable = true;
}
