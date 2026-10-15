"""Cron wrapper for the /intel plugin.

Invoked by hermes' cron scheduler with `--no-agent`: this script *is* the
job, its stdout is delivered verbatim (empty stdout = silent run). Mirrors
pkgs/hermes-plugin-today/morning-today.py — see that file for why the
plugin is loaded as a package via importlib.

Scheduled weekdays only, so Monday's run looks back 72 h to cover the
weekend instead of leaving Fri–Sun entries unread forever.
"""
from __future__ import annotations

import asyncio
import importlib.util
import os
import sys
from datetime import datetime
from pathlib import Path

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/var/lib/hermes/.hermes"))
DAY = 24 * 60 * 60


def _locate_intel_plugin() -> Path:
    primary = HERMES_HOME / "plugins" / "nix-managed-hermes-plugin-intel" / "__init__.py"
    if primary.is_file():
        return primary
    plugins_dir = HERMES_HOME / "plugins"
    if plugins_dir.is_dir():
        for candidate in plugins_dir.iterdir():
            init = candidate / "__init__.py"
            yaml = candidate / "plugin.yaml"
            if init.is_file() and yaml.is_file() and "name: intel" in yaml.read_text():
                return init
    raise FileNotFoundError(
        f"could not locate the intel plugin under {plugins_dir}"
    )


def _load_intel_module():
    init_path = _locate_intel_plugin()
    pkg_name = "hermes_plugin_intel"
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
    mod = _load_intel_module()
    window = 3 * DAY if datetime.now().weekday() == 0 else DAY
    entries_seen = True
    try:
        brief = await mod._run_intel(preview=False, window_seconds=window)
        entries_seen = not brief.startswith("No new entries")
    except Exception as e:  # noqa: BLE001 — surface failures in Signal
        brief = f"intel cron error: {type(e).__name__}: {e}"
    # Nothing published → stay silent rather than ping a "nothing" message.
    if brief and entries_seen:
        sys.stdout.write(brief.rstrip() + "\n")
    return 0


if __name__ == "__main__":
    raise SystemExit(asyncio.run(_main()))
