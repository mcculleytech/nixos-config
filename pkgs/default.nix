{ pkgs, version ? "0.0.0-dev" }:
{
  obsidian-headless = pkgs.callPackage ./obsidian-headless { };
  openwhispr = pkgs.callPackage ./openwhispr { };
}
