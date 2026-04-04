# Go development shell
# Usage: nix develop .#go-dev
{ pkgs }: pkgs.mkShell {
  name = "go-dev";
  nativeBuildInputs = with pkgs; [
    # toolchain
    go
    gopls
    delve
    garble
  ];

  shellHook = ''
    echo "Go dev shell loaded — $(go version)"
  '';
}
