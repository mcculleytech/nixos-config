{ stdenvNoCC, ... }:

# Hermes-agent skill — a SKILL.md the agent can `skill_view()` to load
# alex's vault rules into context. Mirrors the plugin pattern: hermetic
# derivation with no build steps, the hermes-agent nix module symlinks
# $out/SKILL.md into HERMES_HOME/skills/<dir>/SKILL.md at activation.

stdenvNoCC.mkDerivation {
  pname = "hermes-skill-obsidian";
  version = "0.1.0";
  src = ./.;
  dontConfigure = true;
  dontBuild = true;
  installPhase = ''
    mkdir -p $out
    cp SKILL.md $out/
  '';
  meta.description = "Alex's Obsidian vault policy skill for hermes-agent.";
}
