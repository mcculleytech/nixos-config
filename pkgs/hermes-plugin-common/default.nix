{ stdenvNoCC, ... }:

# Shared Python helpers consumed by the in-process hermes plugins.
# Currently ships `aliases.py` — the `/model` alias resolver used by
# `intel` and `today`. Plugin derivations copy individual files out of
# this $out into their own $out so each plugin remains a self-contained
# directory (hermes' loader doesn't follow inter-plugin imports).

stdenvNoCC.mkDerivation {
  pname = "hermes-plugin-common";
  version = "0.1.0";
  src = ./.;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    mkdir -p $out
    cp aliases.py $out/
  '';
  meta.description = "Shared Python helpers for hermes-plugin-* packages.";
}
