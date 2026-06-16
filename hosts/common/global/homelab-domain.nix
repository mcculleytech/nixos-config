{ lib, ... }:
{
  options.lab.homelabDomain = lib.mkOption {
    type = lib.types.str;
    description = ''
      Base domain for homelab services (e.g. <code>home.mcculley.tech</code>).
      Sourced from <code>secrets/git_crypt_traefik.json</code> so the literal
      string lives in the encrypted blob, not in cleartext .nix files.

      All non-traefik consumers should reference this option rather than
      hardcoding the domain. (Traefik itself owns the JSON file and is
      intentionally left as the source of truth.)
    '';
  };

  config.lab.homelabDomain =
    (builtins.fromJSON (builtins.readFile ../../../secrets/git_crypt_traefik.json))
      .traefik.homelab_domain;
}
