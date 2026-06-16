# Prebuilt signal-cli 0.14.5 from the upstream JRE release, with the bundled
# libsignal-client native .so patched for NixOS.
#
# Stopgap: nixpkgs builds signal-cli from source and lags upstream ~2 months
# (stuck at 0.14.3 as of 2026-06-16). A Signal server-side envelope change
# (~2026-06-10) broke sealed-sender receive in every signal-cli < 0.14.5 with
# `getServerGuid(...) must not be null` (NullPointerException, upstream #2059),
# so inbound messages silently vanish before reaching Hermes. 0.14.5
# (2026-06-11) is the fix.
#
# Forward-porting the nixpkgs *source* build would mean regenerating the Gradle
# deps.json AND rebuilding the libsignal Rust JNI (0.94.4, new cargoHash).
# Instead we wrap the upstream JRE distribution: it ships every jar including
# libsignal-client-0.94.4.jar, which bundles `libsignal_jni_amd64.so`. That
# .so is extracted to /tmp and dlopen'd at runtime, and on NixOS it fails to
# load (its NEEDED libstdc++/libgcc_s/libm/libc/ld-linux aren't on the default
# search path). We extract it, let autoPatchelfHook set its rpath, re-inject it
# into the jar, and run the launcher under a Nix JDK.
#
# REMOVE this and revert hosts/.../signal-cli.nix to pkgs.signal-cli once
# nixpkgs ships >= 0.14.5 (the module already tracked unstable, so a flake
# update will carry the proper source build forward).
{ lib, stdenv, fetchurl, autoPatchelfHook, makeWrapper, unzip, zip, jdk25_headless }:

stdenv.mkDerivation (finalAttrs: {
  pname = "signal-cli-bin";
  version = "0.14.5";
  libsignalJar = "libsignal-client-0.94.4.jar";

  src = fetchurl {
    url = "https://github.com/AsamK/signal-cli/releases/download/v${finalAttrs.version}/signal-cli-${finalAttrs.version}.tar.gz";
    hash = "sha256-YtOOv+85iNePQ35zKBg7de5UnRETguZsGvcNPr0816c=";
  };

  nativeBuildInputs = [ autoPatchelfHook makeWrapper unzip zip ];
  # Libraries the bundled libsignal_jni_amd64.so needs (autoPatchelfHook
  # resolves libstdc++/libgcc_s from the gcc lib, libm/libc/ld-linux from glibc).
  buildInputs = [ (lib.getLib stdenv.cc.cc) ];

  installPhase = ''
    runHook preInstall
    mkdir -p $out/share/signal-cli
    cp -r bin lib man $out/share/signal-cli/

    # Stage the native lib loose so fixupPhase's autoPatchelfHook rewrites its
    # rpath; postFixup re-injects it into the jar.
    mkdir -p $out/.jni
    unzip -o -q "$out/share/signal-cli/lib/${finalAttrs.libsignalJar}" \
      libsignal_jni_amd64.so -d $out/.jni
    runHook postInstall
  '';

  postFixup = ''
    # Re-inject the now-patched .so at the same path inside the jar (zip -j
    # would strip the path; we run from $out/.jni so the stored name is bare,
    # matching its jar-root location).
    ( cd $out/.jni && zip -q "$out/share/signal-cli/lib/${finalAttrs.libsignalJar}" libsignal_jni_amd64.so )
    rm -rf $out/.jni

    # Launcher needs a JRE; pin JAVA_HOME to a Nix JDK (signal-cli requires 21+).
    makeWrapper $out/share/signal-cli/bin/signal-cli $out/bin/signal-cli \
      --set JAVA_HOME ${jdk25_headless.home}
  '';

  meta = {
    description = "signal-cli ${finalAttrs.version} (prebuilt JRE dist, libsignal .so patched for NixOS; stopgap until nixpkgs ships >= 0.14.5)";
    homepage = "https://github.com/AsamK/signal-cli";
    license = lib.licenses.gpl3Plus;
    platforms = [ "x86_64-linux" ];
    mainProgram = "signal-cli";
    sourceProvenance = [ lib.sourceTypes.binaryBytecode lib.sourceTypes.binaryNativeCode ];
  };
})
