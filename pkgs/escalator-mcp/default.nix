{ lib
, buildGoModule
, version ? "0.2.0"
}:

buildGoModule {
  pname = "escalator-mcp";
  inherit version;

  src = ./.;

  # Discovered via `nix-build` failing on lib.fakeHash; update if go.sum changes.
  vendorHash = "sha256-Nhj/P8IqRqkX3DiPz58H5Q/iTRIyRM45kg/DCtbM+ME=";

  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "Single-tool MCP for one-shot frontier-model consults via OpenRouter (Go)";
    license = licenses.mit;
    mainProgram = "escalator-mcp";
    platforms = platforms.linux;
  };
}
