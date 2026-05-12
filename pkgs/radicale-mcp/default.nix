{ lib
, python3
}:

python3.pkgs.buildPythonApplication {
  pname = "radicale-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3.pkgs.setuptools ];

  dependencies = with python3.pkgs; [
    mcp
    starlette
    uvicorn
    caldav
    vobject
  ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting a Radicale CalDAV/CardDAV instance";
    license = licenses.mit;
    mainProgram = "radicale-mcp";
    platforms = platforms.linux;
  };
}
