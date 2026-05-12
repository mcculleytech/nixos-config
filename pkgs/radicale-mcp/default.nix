{ lib
, python3
, version ? "0.1.0"
}:

python3.pkgs.buildPythonApplication {
  pname = "radicale-mcp";
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
