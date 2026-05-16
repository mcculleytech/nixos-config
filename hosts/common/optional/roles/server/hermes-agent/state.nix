{ lib, pkgs, config, ... }:
let
  cfg = config.hermes-agent;
in
{
  config = lib.mkIf cfg.enable {
    # The skill expects $HERMES_HOME to exist before sops writes the
    # client_secret file into it. The hermes-agent service would create it
    # on first run, but activation-time sops symlinks land earlier.
    systemd.tmpfiles.rules = [
      # HERMES_HOME has to allow group traversal (0750 not 0700) so
      # gcal-mcp's service user (member of the `hermes` group via
      # extraGroups) can reach the google credential + token files.
      "d /var/lib/hermes/.hermes 0750 alex hermes -"
      "d /var/lib/hermes/.hermes/cron 2770 alex hermes -"
      "d /var/lib/hermes/.hermes/scripts 0750 alex hermes -"
      "d /var/lib/hermes/.hermes/skills/note-taking 0750 alex hermes -"
      # The skill writes google_token.json with the running user's
      # default umask (typically 0600). Force group-readable so gcal-mcp
      # can read it for token refreshes. tmpfiles's `z` mode adjusts an
      # EXISTING file without creating it.
      "z /var/lib/hermes/.hermes/google_token.json 0640 alex hermes -"
      # Cron-script files. `hermes cron --script <name>` validates
      # against $HERMES_HOME/scripts/ AFTER resolving symlinks, so a
      # plain symlink into the nix store gets rejected as escaping the
      # directory. We instead COPY the script content from the plugin
      # derivation on every activation (handled by the activation
      # script below) — pinned to the same store path the plugin ships
      # via restartTriggers + plugin-package hash.
      # Nix-managed skill directory — same `L+` pattern as the
      # cron-script. The skill walker (agent/skill_utils.py) discovers
      # SKILL.md via os.walk(followlinks=True), so a symlink at the
      # SKILL.md *file* level works. Place it under note-taking/ to
      # cohabit with the upstream `obsidian` skill (the model picks the
      # more-specific description on vault-related turns).
      "L+ /var/lib/hermes/.hermes/skills/note-taking/obsidian-vault-policy - - - - ${pkgs.hermes-skill-obsidian}"
    ];

    # Copy plugin-shipped cron scripts as REAL files (not symlinks) so
    # hermes' `_validate_cron_script_path` doesn't reject them after
    # resolving symlinks out of HERMES_HOME/scripts/. Re-runs on every
    # activation, so updates to the plugin source ship via colmena.
    system.activationScripts.hermes-cron-scripts = {
      deps = [ "users" "groups" ];
      text = ''
        ${pkgs.coreutils}/bin/install -D -m 0750 -o alex -g hermes \
          ${pkgs.hermes-plugin-today}/scripts/morning-today.py \
          /var/lib/hermes/.hermes/scripts/morning-today.py
      '';
    };
  };
}
