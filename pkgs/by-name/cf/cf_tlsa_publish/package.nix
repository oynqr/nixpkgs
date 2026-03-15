{
  lib,
  rustPlatform,
  fetchFromGitHub,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "cf_tlsa_publish";
  version = "0.0.1";

  src = fetchFromGitHub {
    owner = "oynqr";
    repo = "cf_tlsa_publish";
    rev = "3516835c3344a786971709e0c09f171192081fb3";
    hash = "sha256-oEF6+3OcBNez2DNDif1SG3PwP+HcTjNzVBpsZT83jzc=";
  };

  cargoHash = "sha256-tJl3EdUHOQsGuTRTm1/gVXk/M5j+IsolSAVLCntcqd4=";

  meta = {
    description = "Small program to facilitate publishing TLSA records to Cloudflare";
    homepage = "https://github.com/oynqr/cf_tlsa_publish";
    license = lib.licenses.agpl3Plus;
    maintainers = with lib.maintainers; [ oynqr ];
    mainProgram = "cf_tlsa_publish";
  };
})
