{ lib
, buildGoModule
, version ? "0.2.0"
}:

buildGoModule {
  pname = "signal-mcp";
  inherit version;

  src = ./.;

  # Discovered via `nix-build` failing on lib.fakeHash; update if go.sum changes.
  # Larger than peer MCPs because modernc.org/sqlite pulls a substantial dep tree.
  vendorHash = "sha256-OYeAnrRmTXbbdZlaoTEe9hhmTk57JwZgtie5RitlYo8=";

  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server for outbound Signal messaging with mandatory approval gate (Go)";
    license = licenses.mit;
    mainProgram = "signal-mcp";
    platforms = platforms.linux;
  };
}
