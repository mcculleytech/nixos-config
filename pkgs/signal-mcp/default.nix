{ lib
, python3
}:

python3.pkgs.buildPythonApplication {
  pname = "signal-mcp";
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
    description = "MCP server for outbound Signal messaging with mandatory approval gate";
    license = licenses.mit;
    mainProgram = "signal-mcp";
    platforms = platforms.linux;
  };
}
