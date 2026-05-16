"""Cron wrapper for the /today plugin.

Invoked by hermes' cron scheduler with `--no-agent`: this script *is* the
job, its stdout is delivered verbatim. We bypass the LLM agent loop
entirely because /today is a deterministic data-gathering plugin —
running it through the agent would just burn tokens for the same output.

Resolution order for the plugin module:
  1. The nix-managed symlink at $HERMES_HOME/plugins/nix-managed-hermes-plugin-today
  2. Fallback: walk plugin dirs looking for one whose plugin.yaml names "today"

We import the plugin file directly via importlib (rather than adding
its parent to sys.path) because the hyphenated directory name isn't a
valid Python package identifier.
"""
from __future__ import annotations

import asyncio
import importlib.util
import os
import sys
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/var/lib/hermes/.hermes"))


def _locate_today_plugin() -> Path:
    primary = HERMES_HOME / "plugins" / "nix-managed-hermes-plugin-today" / "__init__.py"
    if primary.is_file():
        return primary
    plugins_dir = HERMES_HOME / "plugins"
    if plugins_dir.is_dir():
        for candidate in plugins_dir.iterdir():
            init = candidate / "__init__.py"
            yaml = candidate / "plugin.yaml"
            if init.is_file() and yaml.is_file() and "today" in yaml.read_text():
                return init
    raise FileNotFoundError(
        f"could not locate the today plugin under {plugins_dir}"
    )


def _load_today_module():
    """Load the plugin's __init__.py as a *package*, not a bare module.
    The plugin uses relative imports (`from .aliases import …`) which
    only work when the loaded module is part of a package — same
    convention hermes itself uses in `hermes_cli/plugins.py`. So we
    set submodule_search_locations + __package__ + register in
    sys.modules before exec'ing."""
    init_path = _locate_today_plugin()
    pkg_name = "hermes_plugin_today"
    plugin_dir = str(init_path.parent)
    spec = importlib.util.spec_from_file_location(
        pkg_name,
        init_path,
        submodule_search_locations=[plugin_dir],
    )
    if spec is None or spec.loader is None:
        raise ImportError(f"could not build import spec for {init_path}")
    mod = importlib.util.module_from_spec(spec)
    mod.__package__ = pkg_name
    mod.__path__ = [plugin_dir]
    sys.modules[pkg_name] = mod
    spec.loader.exec_module(mod)
    return mod


async def _main() -> int:
    mod = _load_today_module()
    brief = await mod._run_today(raw=False, skip_note=False)
    if brief:
        sys.stdout.write(brief.rstrip() + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
