{
  lib,
  stdenvNoCC,
  fetchurl,
  _7zz,
}:

stdenvNoCC.mkDerivation (finalAttrs: {
  pname = "waddly";
  # nix/update.sh replaces the version and hash lines.
  version = "1.8.0";

  src = fetchurl {
    url = "https://github.com/nyatinte/Waddly/releases/download/v${finalAttrs.version}/Waddly-${finalAttrs.version}-macos-arm64.dmg";
    hash = "sha256-cg2Vc9LGjPYbF92AADZMO77cHb++NhEW2QbXm05cP1M=";
  };

  # The release image is UDZO around an APFS volume. undmg only reads HFS.
  nativeBuildInputs = [ _7zz ];

  unpackPhase = ''
    runHook preUnpack
    7zz x $src -bd -y >/dev/null
    runHook postUnpack
  '';

  sourceRoot = ".";

  dontConfigure = true;
  dontBuild = true;
  # Keep the ad-hoc signature embedded in the Mach-O. The release build is not notarized.
  dontFixup = true;

  installPhase = ''
    runHook preInstall

    mkdir -p $out/Applications $out/bin
    cp -R Waddly.app $out/Applications/
    ln -s ../Applications/Waddly.app/Contents/MacOS/Waddly $out/bin/waddly

    runHook postInstall
  '';

  meta = {
    description = "Desktop pet that reacts to keyboard input";
    homepage = "https://github.com/nyatinte/Waddly";
    changelog = "https://github.com/nyatinte/Waddly/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    sourceProvenance = [ lib.sourceTypes.binaryNativeCode ];
    platforms = [ "aarch64-darwin" ];
    mainProgram = "waddly";
  };
})
