{ lib
, buildGoModule
, version ? "0.2.0"
}:

buildGoModule {
  pname = "miniflux-mcp";
  inherit version;

  src = ./.;

  # Discovered via `nix-build` failing on lib.fakeHash; update if go.sum changes.
  vendorHash = "sha256-Nhj/P8IqRqkX3DiPz58H5Q/iTRIyRM45kg/DCtbM+ME=";

  # ldflags trim build paths from the binary; -s -w drop debug/symbol tables.
  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting a Miniflux RSS reader instance (Go)";
    license = licenses.mit;
    mainProgram = "miniflux-mcp";
    platforms = platforms.linux;
  };
}
