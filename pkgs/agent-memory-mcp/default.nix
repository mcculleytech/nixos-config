{ lib
, python3
, version ? "0.1.0"
}:

python3.pkgs.buildPythonApplication {
  pname = "agent-memory-mcp";
  inherit version;
  pyproject = true;

  src = ./.;

  # Substitute the placeholder in pyproject.toml with the version threaded
  # through from the flake. Bakes the version into the installed package's
  # metadata so importlib.metadata.version() returns it at runtime.
  postPatch = ''
    substituteInPlace pyproject.toml \
      --replace-fail 'version = "0.1.0"' 'version = "${version}"'
  '';

  build-system = [ python3.pkgs.setuptools ];

  dependencies = with python3.pkgs; [
    mcp
    psycopg
    psycopg-c        # binary speedups for psycopg3
    pgvector
    starlette
    uvicorn
    httpx
  ];

  # No upstream tests; we exercise the service via systemd + curl post-deploy.
  doCheck = false;

  meta = with lib; {
    description = "MCP server fronting a pgvector-backed shared agent memory store";
    license = licenses.mit;
    mainProgram = "agent-memory-mcp";
    platforms = platforms.linux;
  };
}
