{ lib
, buildGoModule
, version ? "0.2.0"
}:

buildGoModule {
  pname = "radicale-mcp";
  inherit version;

  src = ./.;

  # Discovered via `nix-build` failing on lib.fakeHash; update if go.sum changes.
  vendorHash = "sha256-n/hkGkSBTsJ+yhOmmObMv5COFOo9DyHJC8WMH3+fayI=";

  # ldflags trim build paths from the binary; -s -w drop debug/symbol tables.
  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting a Radicale CalDAV/CardDAV instance (Go)";
    license = licenses.mit;
    mainProgram = "radicale-mcp";
    platforms = platforms.linux;
  };
}
