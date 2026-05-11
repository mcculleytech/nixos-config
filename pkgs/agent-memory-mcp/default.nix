{ lib
, python3
}:

python3.pkgs.buildPythonApplication {
  pname = "agent-memory-mcp";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

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
