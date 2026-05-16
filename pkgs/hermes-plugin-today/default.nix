{ stdenvNoCC, hermes-plugin-common, ... }:

# Directory-based hermes-agent plugin. See pkgs/hermes-plugin-intel for
# the pattern explanation — same shape: copy plugin.yaml + __init__.py
# into $out/, let hermes-agent's activation symlink it into HERMES_HOME.
#
# Also ships a cron-wrapper script at $out/scripts/morning-today.py.
# The hermes-agent nix module symlinks that into HERMES_HOME/scripts/
# so `hermes cron create ... --script morning-today.py --no-agent`
# resolves to it.
#
# Shares the `/model` alias resolver with intel via hermes-plugin-common.

stdenvNoCC.mkDerivation {
  pname = "hermes-plugin-today";
  version = "0.1.0";
  src = ./.;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    mkdir -p $out $out/scripts
    cp plugin.yaml __init__.py $out/
    cp morning-today.py $out/scripts/
    cp ${hermes-plugin-common}/aliases.py $out/
  '';
  meta.description = "Morning briefing slash command (/today) + daily-note creator.";
}
