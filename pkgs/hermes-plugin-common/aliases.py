"""Shared `/model` alias helpers for in-process hermes plugins.

Two plugins (`intel`, `today`) accept a model-alias argument so the user
can override the synth model per command (`/intel deep`, `/today opus`).
Both resolve the alias against the same `~/.hermes/config.yaml` block
that the gateway uses for `/model <alias>` switching, so there's one
source of truth for the curated short names.

This module is copied into each plugin directory at build time (see
`pkgs/hermes-plugin-intel/default.nix` and the today/spend siblings),
which lets the plugin's `__init__.py` use the relative import
``from .aliases import _model_aliases, _resolve_alias`` — hermes loads
each plugin with `submodule_search_locations` pointed at its own
directory, so sibling `.py` files participate in the same package.
"""
from __future__ import annotations

import logging
import os
from pathlib import Path

log = logging.getLogger("hermes.plugins.aliases")

HERMES_HOME = Path(os.environ.get("HERMES_HOME", "/var/lib/hermes/.hermes"))

_alias_cache: dict | None = None


def _model_aliases() -> dict:
    """Lazy-loaded `/model` alias table from hermes' rendered config.yaml.
    Cached for the life of the process — aliases are baked at deploy
    time, so a fresh config requires a hermes restart anyway."""
    global _alias_cache
    if _alias_cache is None:
        try:
            import yaml
            with (HERMES_HOME / "config.yaml").open() as f:
                cfg = yaml.safe_load(f) or {}
            _alias_cache = cfg.get("model_aliases") or {}
        except Exception as e:  # noqa: BLE001
            log.warning("could not load model_aliases: %s", e)
            _alias_cache = {}
    return _alias_cache


def _resolve_alias(token: str | None) -> dict | None:
    """Resolve a `/model` alias (e.g. `deep`, `pro`) to its full provider
    config. A token containing `/` is treated as a literal OpenRouter
    slug. Returns None when nothing matches."""
    if not token:
        return None
    if "/" in token:
        return {"model": token, "provider": "openrouter"}
    return _model_aliases().get(token)
