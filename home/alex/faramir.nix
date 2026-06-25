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

  # Spotlight + Launchpad only index real .app directories (not symlinks
  # or aliases), so we copy nix-installed apps into ~/Applications.
  # enableChecks=false avoids a sudo .DS_Store probe that can leave
  # root-owned files blocking future rsync updates (home-manager #8067).
  targets.darwin.linkApps.enable = false;
  targets.darwin.copyApps.enable = true;
  targets.darwin.copyApps.enableChecks = false;

  home.packages = with pkgs; [
    direnv
    starship
    fzf
    htop
    jq
    yq
    unstable.antigravity-cli
    transmission_4
    unstable.lmstudio
  ];

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.starship.enable = true;
  programs.fzf.enable = true;
}
