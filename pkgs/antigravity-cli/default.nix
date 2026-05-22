{ lib
, stdenv
, fetchurl
, autoPatchelfHook
, stdenvNoCC
}:

# Google Antigravity CLI — `agy` on PATH. Single statically-laid-out binary
# shipped as a per-platform tarball from storage.googleapis.com. Distinct
# from the Antigravity *IDE* (Electron app, separate distribution).
#
# Upstream auto-updater manifest (used by the in-flight Homebrew cask
# `antigravity-cli` PR Homebrew/homebrew-cask#265183):
#   https://antigravity-cli-auto-updater-974169037036.us-central1.run.app/manifests/<os>_<arch>.json
#
# When bumping: pull the new url + sha256 from each manifest. The build ID
# in the URL ("5288553236791296") is part of the version; livecheck strips
# it back to dotted form.
let
  version = "1.0.0";
  buildId = "5288553236791296";
  baseUrl = "https://storage.googleapis.com/antigravity-public/antigravity-cli/${version}-${buildId}";

  sources = {
    aarch64-darwin = {
      url = "${baseUrl}/darwin-arm/cli_mac_arm64.tar.gz";
      sha256 = "02ij9qvrsp8s1q07kxmdhak3k4g8crcdf7hn7fcfy8bswaszghk5";
    };
    x86_64-darwin = {
      url = "${baseUrl}/darwin-x64/cli_mac_x64.tar.gz";
      sha256 = "0lzvnfgpszs2ly0v3y7dfk8xfi2w2p969mxdwcl6dgzhvhjiljkl";
    };
    x86_64-linux = {
      url = "${baseUrl}/linux-x64/cli_linux_x64.tar.gz";
      sha256 = "1dlyx6vpzw0zsl50v0hwrrsx88jf65bq0g2ddjhc9bsgax0662bh";
    };
  };

  src = fetchurl (sources.${stdenv.hostPlatform.system} or (throw
    "antigravity-cli: unsupported platform ${stdenv.hostPlatform.system}"));
in
stdenvNoCC.mkDerivation {
  pname = "antigravity-cli";
  inherit version src;

  # Tarball is a single executable named `antigravity` at the root, no
  # nested directory. sourceRoot = "." prevents stdenv's default unpacker
  # from looking for one.
  sourceRoot = ".";

  # Linux binary is dynamically linked against the usual glibc/stdc++ set;
  # autoPatchelfHook rewrites the interpreter to the nix store path so it
  # runs outside an FHS environment. macOS Mach-O binaries don't need this.
  nativeBuildInputs = lib.optionals stdenv.hostPlatform.isLinux [ autoPatchelfHook ];

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 antigravity $out/bin/antigravity
    ln -s antigravity $out/bin/agy
    runHook postInstall
  '';

  meta = with lib; {
    description = "Google Antigravity CLI — terminal interface for Antigravity agents (replaces gemini-cli)";
    homepage = "https://antigravity.google/product/antigravity-cli";
    license = licenses.unfree;
    mainProgram = "agy";
    platforms = builtins.attrNames sources;
    sourceProvenance = with sourceTypes; [ binaryNativeCode ];
  };
}
