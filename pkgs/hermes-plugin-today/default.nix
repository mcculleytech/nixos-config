{ stdenvNoCC, ... }:

# Directory-based hermes-agent plugin. See pkgs/hermes-plugin-intel for
# the pattern explanation — same shape: copy plugin.yaml + __init__.py
# into $out/, let hermes-agent's activation symlink it into HERMES_HOME.

stdenvNoCC.mkDerivation {
  pname = "hermes-plugin-today";
  version = "0.1.0";
  src = ./.;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    mkdir -p $out
    cp plugin.yaml __init__.py $out/
  '';
  meta.description = "Morning briefing slash command (/today) + daily-note creator.";
}
