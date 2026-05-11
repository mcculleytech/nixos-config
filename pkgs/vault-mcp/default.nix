{ lib
, python3
}:

python3.pkgs.buildPythonApplication {
  pname = "vault-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3.pkgs.setuptools ];

  dependencies = with python3.pkgs; [
    mcp
    starlette
    uvicorn
  ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting an on-disk Obsidian vault";
    license = licenses.mit;
    mainProgram = "vault-mcp";
    platforms = platforms.linux;
  };
}
