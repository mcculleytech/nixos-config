# Prebuilt signal-cli from the upstream GraalVM native release.
#
# Stopgap: nixpkgs builds signal-cli from source and lags upstream by ~2
# months (stuck at 0.14.3 as of 2026-06-16). A Signal server-side envelope
# change (~2026-06-10) broke sealed-sender receive in every signal-cli
# < 0.14.5 with `getServerGuid(...) must not be null` (NullPointerException,
# upstream #2059), so inbound messages silently vanish before reaching Hermes.
# 0.14.5 (released 2026-06-11) is the fix.
#
# Rather than forward-port the source build (regenerate the Gradle deps.json +
# rebuild the libsignal Rust JNI), we wrap the official `-Linux-native.tar.gz`:
# a single GraalVM-compiled ELF (no JRE, no sidecar libsignal — it's baked into
# the image), dynamically linked against only libc + libz. autoPatchelfHook
# fixes the interpreter/rpath for NixOS.
#
# REMOVE this and revert hosts/.../signal-cli.nix to pkgs.signal-cli once
# nixpkgs ships >= 0.14.5 (the module already tracked unstable, so a flake
# update will carry the proper source build forward).
{ lib, stdenv, fetchurl, autoPatchelfHook, zlib }:

stdenv.mkDerivation (finalAttrs: {
  pname = "signal-cli-bin";
  version = "0.14.5";

  src = fetchurl {
    url = "https://github.com/AsamK/signal-cli/releases/download/v${finalAttrs.version}/signal-cli-${finalAttrs.version}-Linux-native.tar.gz";
    hash = "sha256-OdyeSD2g1pFRBl6HruhIbXqLxn4NPpmUyFEmnBv9gOM=";
  };

  nativeBuildInputs = [ autoPatchelfHook ];
  buildInputs = [ (lib.getLib stdenv.cc.cc) zlib ];

  # Tarball is a single bare executable named `signal-cli`, not a directory.
  sourceRoot = ".";
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 signal-cli $out/bin/signal-cli
    runHook postInstall
  '';

  # GraalVM image is already optimized/stripped; don't let fixup re-strip.
  dontStrip = true;

  meta = {
    description = "signal-cli ${finalAttrs.version} (prebuilt GraalVM native; stopgap until nixpkgs ships >= 0.14.5)";
    homepage = "https://github.com/AsamK/signal-cli";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "signal-cli";
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
  };
})
