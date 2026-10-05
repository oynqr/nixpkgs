{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  qt6Packages,

  apple-sdk_15,
  asciidoctor,
  botan3,
  curl,
  darwinMinVersionHook,
  keyutils,
  libX11,
  libxi,
  libxtst,
  libusb1,
  libxkbcommon,
  minizip,
  nixosTests,
  pcsclite,
  pkg-config,
  qrencode,
  readline,
  wrapGAppsHook3,
  zlib,

  withKeePassBrowser ? true,
  withKeePassFDOSecrets ? stdenv.hostPlatform.isLinux,
  withKeePassNetworking ? true,
  withKeePassSSHAgent ? true,
  withKeePassX11 ? false,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "keepassxc";
  version = "2.8.0-unstable-2026-10-05";

  src = fetchFromGitHub {
    owner = "keepassxreboot";
    repo = "keepassxc";
    rev = "9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd";
    hash = "sha256-fksThYmGZed66zxGDxlS2SHQzJYRf+T9AuZPbaNZV5Y=";
  };

  env = lib.optionalAttrs stdenv.cc.isClang {
    NIX_CFLAGS_COMPILE = toString [
      "-Wno-old-style-cast"
      "-Wno-error"
      "-D__BIG_ENDIAN__=${if stdenv.hostPlatform.isBigEndian then "1" else "0"}"
    ];
  };

  postPatch = lib.optionalString stdenv.hostPlatform.isDarwin ''
    substituteInPlace CMakeLists.txt \
      --replace-fail \
        'elseif(APPLE AND WITH_APP_BUNDLE)' \
        'elseif(APPLE AND WITH_APP_BUNDLE)
    set(CMAKE_INSTALL_PREFIX "''${CMAKE_INSTALL_PREFIX}/Applications")'

    substituteInPlace src/post_install/CMakeLists.txt \
      --replace-fail \
        'if(APPLE AND WITH_APP_BUNDLE)' \
        'if(FALSE)'
  '';

  cmakeFlags = [
    (lib.cmakeFeature "KEEPASSXC_BUILD_TYPE" "Release")
    (lib.cmakeFeature "GIT_HEAD_OVERRIDE" "9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd")

    (lib.cmakeBool "WITH_GUI_TESTS" true)
    (lib.cmakeBool "WITH_X11" withKeePassX11)

    (lib.cmakeBool "KPXC_FEATURE_BROWSER" withKeePassBrowser)
    (lib.cmakeBool "KPXC_FEATURE_SSHAGENT" withKeePassSSHAgent)
    (lib.cmakeBool "KPXC_FEATURE_FDOSECRETS" withKeePassFDOSecrets)
    (lib.cmakeBool "KPXC_FEATURE_NETWORK" withKeePassNetworking)
    (lib.cmakeBool "KPXC_FEATURE_UPDATES" false)
    (lib.cmakeBool "KPXC_FEATURE_DOCS" true)
  ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck

    export LC_ALL="en_US.UTF-8"
    export QT_QPA_PLATFORM=offscreen

    make test ARGS+="-E 'testcli|testgui' --output-on-failure"

    runHook postCheck
  '';

  nativeBuildInputs = [
    asciidoctor
    cmake
    pkg-config
    qt6Packages.qttools
    qt6Packages.wrapQtAppsHook
  ]
  ++ lib.optional (!stdenv.hostPlatform.isDarwin) wrapGAppsHook3;

  dontWrapGApps = true;

  preFixup = ''
    qtWrapperArgs+=("''${gappsWrapperArgs[@]}")
  ''
  + lib.optionalString stdenv.hostPlatform.isDarwin ''
    wrapQtApp "$out/Applications/KeePassXC.app/Contents/MacOS/KeePassXC"
  '';

  postInstall = lib.concatLines [
    (lib.optionalString stdenv.hostPlatform.isDarwin ''
      mkdir -p "$out/bin"
      for program in keepassxc-cli keepassxc-proxy; do
        ln -s "$out/Applications/KeePassXC.app/Contents/MacOS/$program" "$out/bin/$program"
      done
    '')
    (lib.optionalString withKeePassBrowser ''
      mkdir -p "$out/lib/mozilla/native-messaging-hosts"
      substituteAll "${./firefox-native-messaging-host.json}" \
        "$out/lib/mozilla/native-messaging-hosts/org.keepassxc.keepassxc_browser.json"

      mkdir -p "$out/etc/chromium/native-messaging-hosts"
      substituteAll "${./chromium-native-messaging-host.json}" \
        "$out/etc/chromium/native-messaging-hosts/org.keepassxc.keepassxc_browser.json"
    '')
  ];

  buildInputs = [
    botan3
    curl
    libxi
    libxtst
    minizip
    pcsclite
    qrencode
    readline
    zlib

    qt6Packages.qtbase
    qt6Packages.qtsvg
  ]
  ++ lib.optionals stdenv.hostPlatform.isDarwin [
    apple-sdk_15

    # ScreenCaptureKit is used by the macOS implementation.
    (darwinMinVersionHook "12.3")
  ]
  ++ lib.optionals stdenv.hostPlatform.isLinux [
    keyutils
    libusb1
    libxkbcommon
  ]
  ++ lib.optionals withKeePassX11 [
    libX11
  ];

  passthru = {
    tests = {
      inherit (nixosTests) keepassxc;
    };
  };

  meta = {
    description = "Offline password manager with many features";
    longDescription = ''
      A community fork of KeePassX, which is itself a port of KeePass Password Safe.
      The goal is to extend and improve KeePassX with new features and bugfixes,
      to provide a feature-rich, fully cross-platform and modern open-source password manager.
      Accessible via native cross-platform GUI, CLI, has browser integration
      using the KeePassXC Browser Extension (https://github.com/keepassxreboot/keepassxc-browser)
    '';
    homepage = "https://keepassxc.org/";
    donationPage = "https://keepassxc.org/donate/";
    changelog = "https://github.com/keepassxreboot/keepassxc/commit/9e0f57a4a4c6c629fa6d0a593acb7d089b1d95cd";
    license = lib.licenses.gpl2Plus;
    mainProgram = "keepassxc";
    maintainers = with lib.maintainers; [
      sigmasquadron
      ryand56
    ];
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
