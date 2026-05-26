{ lib
, buildGoModule
, version ? "0.2.0"
}:

buildGoModule {
  pname = "gcal-mcp";
  inherit version;

  src = ./.;

  # Discovered via `nix-build` failing on lib.fakeHash; update if go.sum changes.
  # Google API libraries pull a substantial vendor closure.
  vendorHash = "sha256-YcH/VP9x4/IS5dDN00c3ADWOpDTofcxZP7/OHas4fH0=";

  # ldflags trim build paths from the binary; -s -w drop debug/symbol tables.
  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting Google Calendar via existing OAuth credentials (Go)";
    license = licenses.mit;
    mainProgram = "gcal-mcp";
    platforms = platforms.linux;
  };
}
