{
  lib,
  stdenv,
  fetchFromGitHub,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_11,
  nodejs-slim_24,
  python3,
  jq,
  makeWrapper,
  nix-update-script,
  nixosTests,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "aiostreams";
  version = "2.38.1";

  src = fetchFromGitHub {
    owner = "Viren070";
    repo = "AIOStreams";
    tag = "v${finalAttrs.version}";
    hash = "sha256-p0BCG5bZHVa6CPJ95BcooQThy31AgeL3ypjRyfyLK+w=";
  };

  pnpmWorkspaces = [
    "@aiostreams/server..."
    "@aiostreams/frontend..."
    "@aiostreams/web..."
  ];

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs)
      pname
      version
      src
      pnpmWorkspaces
      ;
    pnpm = pnpm_11;
    fetcherVersion = 5;
    hash = "sha256-vbMhn8IPdVeE5KjcjB/HeLvjcJes8BuzW9zb80vGZOY=";
  };

  strictDeps = true;

  nativeBuildInputs = [
    nodejs-slim_24
    pnpm_11
    pnpmConfigHook
    python3
    jq
    makeWrapper
  ];

  buildPhase = ''
    runHook preBuild

    pnpm build
    rm -rf node_modules packages/*/node_modules
    pnpm install --offline --prod --frozen-lockfile --ignore-scripts --filter "@aiostreams/server..."
    pnpm rebuild -r yencode
    find packages/crypto/build node_modules/.pnpm/yencode@*/node_modules/yencode/build -maxdepth 1 -type f -delete
    jq '{version, description, tag: "v\(.version)"}' package.json > resources/metadata.json

    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall

    mkdir -p $out/lib/aiostreams
    cp -r --parents package.json node_modules resources packages/{core,crypto,server,frontend/dist,web/dist} $out/lib/aiostreams
    cp -r packages/server/src/static $out/lib/aiostreams/packages/server/dist
    makeWrapper ${lib.getExe nodejs-slim_24} $out/bin/aiostreams \
      --add-flags $out/lib/aiostreams/packages/server/dist/server.js

    runHook postInstall
  '';

  passthru = {
    updateScript = nix-update-script { };
    tests = { inherit (nixosTests) aiostreams; };
  };

  meta = {
    description = "Consolidates multiple Stremio addons and debrid services into a single addon";
    homepage = "https://github.com/Viren070/AIOStreams";
    changelog = "https://github.com/Viren070/AIOStreams/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.agpl3Only;
    maintainers = with lib.maintainers; [ oynqr ];
    mainProgram = "aiostreams";
    platforms = lib.platforms.linux;
    sourceProvenance = with lib.sourceTypes; [
      fromSource
      binaryNativeCode
    ];
  };
})
