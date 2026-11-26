{
  lib,
  buildGoModule,
  fetchFromGitHub,
  stdenvNoCC,
  fetchPnpmDeps,
  pnpmConfigHook,
  pnpm_10,
  nodejs-slim,
  makeWrapper,
  gitMinimal,
  ffmpeg-headless,
  nix-update-script,
  nixosTests,
}:

buildGoModule (finalAttrs: {
  pname = "stremthru";
  version = "0.105.4";

  src = fetchFromGitHub {
    owner = "MunifTanjim";
    repo = "stremthru";
    tag = finalAttrs.version;
    hash = "sha256-BZng58xsUkrEMoCB0X/UUzA3e/a1p2nXpFcZN4AtJ2I=";
  };

  proxyVendor = true;

  vendorHash = "sha256-w+5SCmlQFf9SpAJU5DScCszyFWH1KXMOV/rZsG1XJow=";

  pnpmDeps = fetchPnpmDeps {
    inherit (finalAttrs) pname version src;
    pnpm = pnpm_10;
    pnpmWorkspaces = [ "dash" ];
    fetcherVersion = 5;
    hash = "sha256-Sdmh0ByLpNbziwyEFWQiFL7NgcoFyjSiLAZas1MBKKE=";
  };

  dash = stdenvNoCC.mkDerivation {
    pname = "${finalAttrs.pname}-dash";
    inherit (finalAttrs) version src pnpmDeps;

    pnpmWorkspaces = [ "dash" ];

    nativeBuildInputs = [
      nodejs-slim
      pnpm_10
      pnpmConfigHook
    ];

    buildPhase = ''
      runHook preBuild

      substituteInPlace node_modules/.pnpm/@tanstack+router-core@*/node_modules/@tanstack/router-core/dist/esm/ssr/ssr-server.js \
        --replace-fail "u: match.updatedAt" "u: 0"
      pnpm --filter dash exec vite build

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      cp -r apps/dash/.output/public $out

      runHook postInstall
    '';
  };

  tags = [
    "sqlite_fts5"
    "sqlite_stat4"
  ];

  ldflags = [
    "-s"
    "-w"
  ];

  nativeBuildInputs = [ makeWrapper ];

  preConfigure = ''
    cp -r ${finalAttrs.dash}/. internal/dash/fs
  '';

  postInstall = ''
    wrapProgram $out/bin/stremthru \
      --set-default STREMTHRU_ENV prod \
      --prefix PATH : ${
        lib.makeBinPath [
          gitMinimal
          ffmpeg-headless
        ]
      }
  '';

  passthru = {
    updateScript = nix-update-script { };
    tests = { inherit (nixosTests) stremthru; };
  };

  meta = {
    description = "Companion for Stremio";
    homepage = "https://docs.stremthru.13377001.xyz";
    changelog = "https://github.com/MunifTanjim/stremthru/blob/${finalAttrs.src.tag}/CHANGELOG.md";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ oynqr ];
    mainProgram = "stremthru";
  };
})
