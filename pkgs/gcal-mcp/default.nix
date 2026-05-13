{ lib
, python3
, version ? "0.1.0"
}:

python3.pkgs.buildPythonApplication {
  pname = "gcal-mcp";
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
    google-api-python-client
    google-auth
    google-auth-oauthlib
  ];

  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting Google Calendar via existing OAuth credentials";
    license = licenses.mit;
    mainProgram = "gcal-mcp";
    platforms = platforms.linux;
  };
}
