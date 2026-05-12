{ lib
, python3
}:

python3.pkgs.buildPythonApplication {
  pname = "miniflux-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3.pkgs.setuptools ];

  dependencies = with python3.pkgs; [
    mcp
    starlette
    uvicorn
    httpx
  ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting a Miniflux RSS reader instance";
    license = licenses.mit;
    mainProgram = "miniflux-mcp";
    platforms = platforms.linux;
  };
}
