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
    hash = lib.fakeHash;
  };

  cargoHash = lib.fakeHash;

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

  postPatch = ''
    # monty crate's lib.rs uses include_str!("../../../README.md") which fails
    # under the flattened cargo vendor layout. Replace with empty string.
    if [ -d vendor ]; then
      find vendor -path '*/monty-*/src/lib.rs' -exec \
        sed -i 's|include_str!("../../../README.md")|""|g' {} \;
    fi
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

  checkFlags = [
    # Tests requiring filesystem locations outside the sandbox or the network.
    "--skip=channels::signal::tests::validate_attachment_paths_accepts_normal_paths"
    "--skip=orchestrator::job_manager::tests::test_validate_bind_mount_rejects_outside_base"
    "--skip=orchestrator::job_manager::tests::test_validate_bind_mount_valid_path"
    "--skip=tools::builtin::job::tests::test_resolve_project_dir_auto"
    "--skip=tools::builtin::job::tests::test_resolve_project_dir_explicit_under_base"
    "--skip=tools::builtin::job::tests::test_resolve_project_dir_rejects_outside_base"
    "--skip=tools::builtin::job::tests::test_resolve_project_dir_rejects_outside_base_existing"
    "--skip=tools::builtin::message::tests::message_tool_passes_attachment_to_broadcast"
    "--skip=tools::builtin::message::tests::message_tool_passes_multiple_attachments_to_broadcast"
    "--skip=tools::builtin::message::tests::message_tool_with_attachments_inside_sandbox_no_channel"
    "--skip=tools::builtin::shell::tests::test_large_output_command"
    "--skip=tools::mcp::auth::tests::test_validate_url_safe_https"
  ];

  meta = with lib; {
    description = "Privacy-first agent OS with WASM tool sandbox and capability-based permissions";
    homepage = "https://github.com/nearai/ironclaw";
    license = with licenses; [ asl20 mit ];
    mainProgram = "ironclaw";
    platforms = platforms.darwin ++ platforms.linux;
  };
}
