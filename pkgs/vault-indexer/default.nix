{ lib
, python3
, version ? "0.1.0"
}:

python3.pkgs.buildPythonApplication {
  pname = "vault-indexer";
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
