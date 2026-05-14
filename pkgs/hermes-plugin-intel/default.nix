{ stdenvNoCC, ... }:

# Directory-based hermes-agent plugin. The upstream nixosModule's
# `extraPlugins` option symlinks each package's $out into
# `$HERMES_HOME/plugins/<name>/`, then hermes discovers plugins by
# scanning for `plugin.yaml`. So all we need is a derivation that
# exposes `plugin.yaml` and `__init__.py` at $out/'s root.
#
# Using stdenvNoCC + a simple installPhase keeps this hermetic (no
# compilers, no patchShebangs) — the plugin is pure-Python, runtime
# deps come from hermes-agent's sealed venv (httpx is already in).

stdenvNoCC.mkDerivation {
  pname = "hermes-plugin-intel";
  version = "0.1.0";
  src = ./.;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    mkdir -p $out
    cp plugin.yaml __init__.py $out/
  '';
  meta.description = "Red-team intel briefing slash command (/intel) for hermes-agent.";
}
