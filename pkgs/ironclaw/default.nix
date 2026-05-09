{ lib
, fetchFromGitHub
, rustPlatform
, pkg-config
, cmake
, clang
, openssl
, sqlite
, stdenv
, darwin ? null
}:

rustPlatform.buildRustPackage rec {
  pname = "ironclaw";
  version = "0.28.0";

  src = fetchFromGitHub {
    owner = "nearai";
    repo = "ironclaw";
    rev = "ironclaw-v${version}";
    hash = "sha256-pKpTswuf7O3hyOmfAJbQXlDpDNKUuEkCP6jg2Q6Inoo=";
  };

  cargoHash = "sha256-uf5RDby26wNeewJPqcXtmEuCsGRuJ7fQd+0qfMpXPOE=";

  nativeBuildInputs = [
    pkg-config
    cmake
    clang
    rustPlatform.bindgenHook
  ];

  buildInputs = [
    openssl
    sqlite
  ] ++ lib.optionals stdenv.isDarwin (
    with darwin.apple_sdk.frameworks; [ Security SystemConfiguration CoreFoundation ]
  );

  postConfigure = ''
    # cargoSetupHook copies the vendor dir with cp -ra, preserving the nix
    # store's 444 permissions. Make files writable before patching.
    find /build -maxdepth 1 -name '*-vendor' -type d \
      -exec chmod -R u+w {} \; 2>/dev/null || true
    # monty (git dep) resolves include_str!("../../../README.md") from src/,
    # 3 levels up to vendor-root/README.md which doesn't exist in the vendor
    # layout. Replace the macro call with an empty string literal.
    find /build -path '*/monty-*/src/lib.rs' -exec \
      sed -i 's|include_str!("../../../README.md")|""|g' {} \;
  '';

  env = {
    OPENSSL_NO_VENDOR = "1";
  };

  cargoBuildFlags = [
    "--bin"
    "ironclaw"
    "--no-default-features"
    "--features"
    "postgres,libsql,html-to-markdown"
  ];

  # Too many tests require filesystem paths outside the nix sandbox or network
  # access. Skip the test suite entirely — we only need the binary.
  doCheck = false;

  meta = with lib; {
    description = "Privacy-first agent OS with WASM tool sandbox and capability-based permissions";
    homepage = "https://github.com/nearai/ironclaw";
    license = with licenses; [ asl20 mit ];
    mainProgram = "ironclaw";
    platforms = platforms.darwin ++ platforms.linux;
  };
}
