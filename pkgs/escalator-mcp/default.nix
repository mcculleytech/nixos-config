{ lib
, python3
, version ? "0.1.0"
}:

python3.pkgs.buildPythonApplication {
  pname = "escalator-mcp";
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
    description = "MCP exposing a consult_expert tool for one-shot frontier-model queries via OpenRouter";
    license = licenses.mit;
    mainProgram = "escalator-mcp";
    platforms = platforms.linux;
  };
}
