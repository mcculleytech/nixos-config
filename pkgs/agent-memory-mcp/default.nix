{ lib
, buildGoModule
, version ? "0.2.0"
}:

buildGoModule {
  pname = "agent-memory-mcp";
  inherit version;

  src = ./.;

  # Discovered via `nix-build` failing on lib.fakeHash; update if go.sum changes.
  vendorHash = "sha256-/PNlrv0e+rJAHdvqWUUrZq5xCStld4DXtYLS3tct+g0=";

  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting a pgvector-backed shared agent memory store (Go)";
    license = licenses.mit;
    mainProgram = "agent-memory-mcp";
    platforms = platforms.linux;
  };
}
