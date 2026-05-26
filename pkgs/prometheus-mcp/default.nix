{ lib
, buildGoModule
, version ? "0.2.0"
}:

buildGoModule {
  pname = "prometheus-mcp";
  inherit version;

  src = ./.;

  # Shared mark3labs/mcp-go dep tree with miniflux-mcp / escalator-mcp.
  vendorHash = "sha256-Nhj/P8IqRqkX3DiPz58H5Q/iTRIyRM45kg/DCtbM+ME=";

  ldflags = [ "-s" "-w" ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting Prometheus (and optionally Alertmanager) (Go)";
    license = licenses.mit;
    mainProgram = "prometheus-mcp";
    platforms = platforms.linux;
  };
}
