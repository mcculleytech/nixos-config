{ lib
, python3
, version ? "0.1.0"
}:

python3.pkgs.buildPythonApplication {
  pname = "prometheus-mcp";
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
    description = "MCP server fronting a Prometheus + Alertmanager instance";
    license = licenses.mit;
    mainProgram = "prometheus-mcp";
    platforms = platforms.linux;
  };
}
