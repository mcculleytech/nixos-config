# C malware development shell
# Usage: nix develop .#c-maldev
{ pkgs }: pkgs.mkShell {
  name = "c-maldev";
  nativeBuildInputs = with pkgs; [
    # compilers
    gcc
    clang
    pkgsCross.mingwW64.stdenv.cc

    # build tools
    gnumake
    cmake
    pkg-config

    # assembler
    nasm

    # debugging
    gdb
    rizin

    # crypto
    openssl

    # utilities
    binutils
    file
    hexdump
  ];

  shellHook = ''
    echo "C maldev shell loaded"
    echo "  mingw cross-compiler: x86_64-w64-mingw32-gcc"
  '';
}
