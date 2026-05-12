{ lib
, python3
}:

python3.pkgs.buildPythonApplication {
  pname = "vault-indexer";
  version = "0.1.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3.pkgs.setuptools ];

  dependencies = with python3.pkgs; [
    mcp
    httpx
  ];

  doCheck = false;

  meta = with lib; {
    description = "Periodic chunker + embedder mirroring an Obsidian vault into agent_memory";
    license = licenses.mit;
    mainProgram = "vault-indexer";
    platforms = platforms.linux;
  };
}
