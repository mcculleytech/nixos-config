{ lib, fetchurl, appimageTools, makeWrapper, ... }:

# OpenWhispr — Electron-based voice-to-text dictation app.
# Upstream: https://github.com/OpenWhispr/openwhispr
#
# Built from source would require a 100+ hour packaging effort: the
# prebuild script downloads whisper-cpp, llama-server, sherpa-onnx,
# qdrant, diarization-models, etc., plus electron-builder, plus native
# compilation. Wrapping the upstream AppImage is the pragmatic choice
# and the standard nixpkgs pattern for unbuildable Electron apps.
#
# Version bumps: change `version`, then refresh `hash` via
#   nix-prefetch-url --type sha256 <new url>

let
  pname = "openwhispr";
  version = "1.7.2";

  src = fetchurl {
    url = "https://github.com/OpenWhispr/openwhispr/releases/download/v${version}/OpenWhispr-${version}-linux-x86_64.AppImage";
    hash = "sha256-EPJTZFtd2bQ026KNcI/FOHfoAMu96HKfJxTPceTc5jw=";
  };

  appimageContents = appimageTools.extract {
    inherit pname version src;
  };
in
appimageTools.wrapType2 {
  inherit pname version src;

  extraInstallCommands = ''
    # Upstream uses hyphenated names (open-whispr.{desktop,png}).
    install -Dm444 ${appimageContents}/open-whispr.desktop \
      $out/share/applications/${pname}.desktop
    install -Dm444 ${appimageContents}/usr/share/icons/hicolor/256x256/apps/open-whispr.png \
      $out/share/icons/hicolor/256x256/apps/${pname}.png
    substituteInPlace $out/share/applications/${pname}.desktop \
      --replace-quiet 'Exec=AppRun --no-sandbox %U' "Exec=${pname} %U" \
      --replace-quiet 'Exec=AppRun %U' "Exec=${pname} %U" \
      --replace-quiet 'Exec=AppRun' "Exec=${pname}" \
      --replace-quiet 'Icon=open-whispr' "Icon=${pname}"
  '';

  meta = with lib; {
    description = "Open-source voice-to-text dictation app (Electron)";
    homepage = "https://openwhispr.com/";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = pname;
  };
}
