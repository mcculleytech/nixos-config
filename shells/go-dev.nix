# Go development shell
# Usage: nix develop .#go-dev
{ pkgs }: pkgs.mkShell {
  name = "go-dev";
  nativeBuildInputs = with pkgs; [
    # toolchain
    go
    gopls
    delve
    # garble — disabled until it supports Go 1.25+ (linker patches not yet available)
  ];

  shellHook = ''
    echo "Go dev shell loaded — $(go version)"
  '';
}
