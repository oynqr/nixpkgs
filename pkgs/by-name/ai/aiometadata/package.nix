{
  lib,
  stdenv,
  buildNpmPackage,
  fetchNpmDeps,
  fetchFromGitHub,
  nodejs_24,
  nodejs-slim_24,
  makeWrapper,
  autoPatchelfHook,
  nix-update-script,
}:

buildNpmPackage (finalAttrs: {
  pname = "aiometadata";
  version = "4.1.0";

  src = fetchFromGitHub {
    owner = "cedya77";
    repo = "aiometadata";
    tag = "v${finalAttrs.version}";
    hash = "sha256-cbCr6Pn2rZpwg8ArsYI9HAEkikujdrewJeiDzjlmVG0=";
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    hash = "sha256-m6r3tDpv9AxxVSdJ/sSVS6PnFmVNjeu+Gi1q7l7+qFQ=";
    dontConfigure = true;
  };

  nodejs = nodejs_24;

  postPatch = ''
    substituteInPlace addon/lib/runtimePaths.js \
      --replace-fail "process.cwd()" "path.join(__dirname, '../../..')"
  '';

  dontConfigure = true;

  nativeBuildInputs = [
    nodejs-slim_24
    makeWrapper
    autoPatchelfHook
  ];

  buildInputs = [ stdenv.cc.cc.lib ];

  preBuild = ''
    rm -r node_modules/bcrypt/prebuilds
    npm rebuild bcrypt
  '';

  postBuild = ''
    npm run build:backend
  '';

  installPhase = ''
    runHook preInstall

    npm prune --omit=dev --no-save
    find node_modules/{bcrypt,better-sqlite3} \( -name "*.mk" -o -name Makefile -o -name config.gypi -o -name .deps -o -name obj.target -o -name test_extension.node \) -prune -exec rm -r {} +
    mkdir -p $out/lib/aiometadata
    cp -r package.json dist public node_modules LICENSE* LICENSING.md NOTICE TRADEMARKS.md THIRD_PARTY_NOTICES.txt $out/lib/aiometadata
    makeWrapper ${lib.getExe nodejs-slim_24} $out/bin/aiometadata \
      --add-flags $out/lib/aiometadata/dist/server/server.js

    runHook postInstall
  '';

  dontAutoPatchelf = true;

  postFixup = ''
    ln -s ${stdenv.cc.cc.lib}/lib/{libstdc++.so.6,libgcc_s.so.1} $out/lib/aiometadata/node_modules/@img/sharp-libvips-linux*/lib
    autoPatchelf $out/lib/aiometadata/node_modules/@antoniomuso
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Metadata provider addon for Stremio";
    homepage = "https://github.com/cedya77/aiometadata";
    changelog = "https://github.com/cedya77/aiometadata/releases/tag/v${finalAttrs.version}";
    license = with lib.licenses; [
      agpl3Plus
      fsl11Asl20
    ];
    maintainers = with lib.maintainers; [ oynqr ];
    mainProgram = "aiometadata";
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
})
