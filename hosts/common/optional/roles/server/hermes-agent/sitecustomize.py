"""Inject locales/ into agent.i18n at Python startup.

Hermes-agent's upstream wheel omits the locales/ YAML files, so the
agent's i18n module returns raw keys for every translatable string
(`gateway.model.switched`, etc.). This sitecustomize.py runs during
site initialization — before any user code, before hermes-agent's
own modules import — imports the i18n module, and monkey-patches its
`_locales_dir` function to point at the YAML catalogs we copied out
of the source tree at activation time.

The companion `localesPatch` derivation in the hermes-agent nix
module copies this file into the venv's PYTHONPATH and copies the
upstream `locales/` directory next to it; the HERMES_LOCALES_DIR
env var resolves at runtime to the latter.
"""
import os
from pathlib import Path

_override = Path(os.environ.get("HERMES_LOCALES_DIR", ""))
if _override.is_dir():
    try:
        import agent.i18n as _i18n_mod  # noqa: E402
        _i18n_mod._locales_dir = lambda: _override
        # Invalidate any cached catalog if i18n already lazily-loaded one.
        for _cache_attr in ("_CATALOGS", "_catalogs", "_CACHE"):
            if hasattr(_i18n_mod, _cache_attr):
                getattr(_i18n_mod, _cache_attr).clear()
    except ImportError:
        # hermes-agent isn't on the path — quietly do nothing.
        pass
