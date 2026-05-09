{ pkgs }:
{
  ironclaw = pkgs.callPackage ./ironclaw { rustPlatform = pkgs.unstable.rustPlatform; };
}
