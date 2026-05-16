"""Site-startup patches for hermes-agent's upstream package.

Two surgical monkey-patches applied during Python's site initialization
(before hermes' own modules import):

  1. Inject locales/ into agent.i18n — upstream's wheel forgets to ship
     locales/, so without this every translatable string returns its raw
     key (`gateway.model.switched`, …).

  2. Prepend alex's `/model` alias list to the gateway's bare `/model`
     response on platforms without an interactive picker (Signal). Bare
     `/model` then returns the alias reference table *plus* the upstream
     provider listing, so you don't have to remember which alias maps to
     which slug. Pure additive — alias resolution itself is already wired
     into `model_switch.py`'s `DirectAlias` path.
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


# ─── /model alias reference patch ───────────────────────────────────────────
def _render_alias_block() -> str:
    """Format alex's `/model` aliases as a markdown block. Tags the alias
    whose model matches the gateway's configured default. Returns empty
    string when no aliases are configured or config.yaml is unreadable."""
    try:
        import yaml
    except ImportError:
        return ""
    hermes_home = Path(os.environ.get("HERMES_HOME", "/var/lib/hermes/.hermes"))
    cfg_path = hermes_home / "config.yaml"
    try:
        with cfg_path.open() as f:
            cfg = yaml.safe_load(f) or {}
    except OSError:
        return ""
    aliases = cfg.get("model_aliases") or {}
    if not aliases:
        return ""
    default_model = ((cfg.get("model") or {}).get("default") or "").strip()
    width = max((len(k) for k in aliases), default=0)
    lines = ["*Aliases:*"]
    for name in sorted(aliases):
        entry = aliases[name] or {}
        model = entry.get("model", "?")
        provider = entry.get("provider", "")
        tags = []
        if model == default_model:
            tags.append("default")
        if provider == "custom":
            base = entry.get("base_url", "")
            tags.append(f"custom: {base}")
        tail = f"  _({', '.join(tags)})_" if tags else ""
        lines.append(f"  `{name.ljust(width)}` → `{model}`{tail}")
    return "\n".join(lines)


try:
    from gateway import run as _gw_run

    _orig_handle_model = _gw_run.GatewayRunner._handle_model_command

    async def _patched_handle_model(self, event):
        raw_args = event.get_command_args().strip()
        result = await _orig_handle_model(self, event)
        # Only inject on bare `/model` (no args), and only when the upstream
        # path actually returned text (the picker path returns None — the
        # adapter handles output asynchronously). Signal has no picker, so
        # this is the common Signal case.
        if not raw_args and isinstance(result, str):
            block = _render_alias_block()
            if block:
                return f"{block}\n\n{result}"
        return result

    _gw_run.GatewayRunner._handle_model_command = _patched_handle_model
except ImportError:
    # gateway package not present — running under cli.py only, skip.
    pass
