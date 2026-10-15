{ stdenvNoCC, hermes-plugin-common, ... }:

# Directory-based hermes-agent plugin. The upstream nixosModule's
# `extraPlugins` option symlinks each package's $out into
# `$HERMES_HOME/plugins/<name>/`, then hermes discovers plugins by
# scanning for `plugin.yaml`. So all we need is a derivation that
# exposes `plugin.yaml`, `__init__.py`, and any sibling helpers at
# $out/'s root.
#
# `aliases.py` is copied from hermes-plugin-common so the resolution
# logic for `/model` aliases stays single-source across plugins —
# `__init__.py` imports it via `from .aliases import …` (hermes loads
# each plugin with submodule_search_locations pointed at its own dir).
#
# Also ships a cron-wrapper script at $out/scripts/weekday-intel.py,
# copied into HERMES_HOME/scripts/ by the hermes-agent module (same
# pattern as hermes-plugin-today's morning-today.py).

stdenvNoCC.mkDerivation {
  pname = "hermes-plugin-intel";
  version = "0.1.0";
  src = ./.;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    mkdir -p $out $out/scripts
    cp plugin.yaml __init__.py $out/
    cp weekday-intel.py $out/scripts/
    cp ${hermes-plugin-common}/aliases.py $out/
  '';
  meta.description = "Red-team intel briefing slash command (/intel) for hermes-agent.";
}
