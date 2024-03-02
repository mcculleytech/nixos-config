{ pkgs ? import <nixpkgs> {} }:

with pkgs;

mkShell {
  nativeBuildInputs = [
    aiodnsbrute
    amass
    bind
    dnsenum
    dnsmon-go
    dnsmonster
    dnsrecon
    dnstake
    dnstracer
    dnstwist
    dnspeep
    dnsx
    fierce
    findomain
    knockpy
    subfinder
    subzerod
  ];
}
