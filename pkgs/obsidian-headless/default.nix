{ lib
, fetchurl
, buildNpmPackage
, nodejs_22
, python3
, makeWrapper
}:

buildNpmPackage rec {
  pname = "obsidian-headless";
  version = "0.0.8";

  src = fetchurl {
    url = "https://registry.npmjs.org/obsidian-headless/-/obsidian-headless-${version}.tgz";
    hash = "sha256-+fg6tr69/7n73KhlJxAb4ujMOvH64hLwIt/6MeAiNtU=";
  };

  # The upstream tarball doesn't ship a lock file. We generated one once via
  # `npm install --package-lock-only` against the published package.json and
  # check it in here. Refresh by re-running and updating npmDepsHash.
  postPatch = ''
    cp ${./package-lock.json} ./package-lock.json
  '';

  npmDepsHash = "sha256-/g3PV+VJ7zotOn70a3J6lJR5Bz0v24vyI540Pe10MJI=";

  nodejs = nodejs_22;

  # No build step — cli.js is already a bundled artifact. Just install.
  dontNpmBuild = true;

  # better-sqlite3 ships a prebuilt binary for our triple; if it falls back to
  # build-from-source it needs python3 + a C++ toolchain (in stdenv already).
  nativeBuildInputs = [ python3 makeWrapper ];

  # buildNpmPackage's default install lays out node_modules + bin under
  # $out/lib/node_modules/<pname>; the `bin` field in package.json
  # ("ob" -> "cli.js") creates $out/bin/ob automatically. We just need to
  # ensure node is reachable on PATH for the shebang.
  postInstall = ''
    wrapProgram $out/bin/ob \
      --prefix PATH : ${lib.makeBinPath [ nodejs_22 ]}
  '';

  meta = with lib; {
    description = "Headless Obsidian Sync client (Dynalist Inc.) — pure sync daemon, no GUI";
    homepage = "https://github.com/obsidianmd/obsidian-headless";
    license = licenses.unfree;
    mainProgram = "ob";
    platforms = platforms.linux;
  };
}
