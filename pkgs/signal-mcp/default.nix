{ lib
, python3
, version ? "0.1.0"
}:

python3.pkgs.buildPythonApplication {
  pname = "signal-mcp";
  inherit version;
  pyproject = true;

  src = ./.;

  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'version = "0.1.0"' 'version = "${version}"'
  '';

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
