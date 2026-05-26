{ lib
, buildGoModule
, version ? "0.1.0"
}:

buildGoModule {
  pname = "email-mcp";
  inherit version;

  src = ./.;

  # Discovered via `nix-build` failing on lib.fakeHash; update if go.sum changes.
  # Larger than peer MCPs because modernc.org/sqlite pulls a substantial dep tree.
  vendorHash = "sha256-GEx/gls+BMfryyeN3Q/Es+DTQOtIE6GoGqibq/YoHSM=";

  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "IMAP/SMTP email MCP server with mandatory send approval gate (Go)";
    license = licenses.mit;
    mainProgram = "email-mcp";
    platforms = platforms.linux;
  };
}
