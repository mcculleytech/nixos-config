"""Prometheus MCP server.

Thin streamable-HTTP MCP wrapper over Prometheus's `/api/v1/*` and (optionally)
Alertmanager's `/api/v2/*` endpoints. Read-only: every tool is a GET against
the upstream, never POST. The agent can query metrics, list scrape targets,
read firing alerts, and walk label/series metadata — but it cannot silence
alerts, push samples, or mutate rule configuration.

Auth model mirrors miniflux-mcp / vault-mcp / signal-mcp:
  * Bearer-token at the MCP layer, validated against a sops-managed
    `tokens` JSON map keyed by client name.
  * No auth toward upstream Prometheus — the homelab deployment is
    tailnet-only with no Prometheus-side basic-auth. If that changes,
    add `PROMETHEUS_MCP_BEARER` and forward it.
"""

from __future__ import annotations

import json
import logging
import os
import subprocess
import sys
from contextlib import asynccontextmanager
from importlib.metadata import PackageNotFoundError, version as _pkg_version
from typing import Any

try:
    __version__ = _pkg_version("prometheus-mcp")
except PackageNotFoundError:
    __version__ = "0.0.0-dev"

import httpx
import uvicorn
from mcp.server.fastmcp import FastMCP
from starlette.applications import Starlette
from starlette.middleware import Middleware
from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import JSONResponse
from starlette.routing import Mount, Route

log = logging.getLogger("prometheus_mcp")


class Config:
    def __init__(self) -> None:
        self.bind_ip = os.environ.get("PROMETHEUS_MCP_BIND_IP", "auto")
        self.port = int(os.environ.get("PROMETHEUS_MCP_PORT", "4287"))
        self.tokens_file = os.environ["PROMETHEUS_MCP_TOKENS_FILE"]
        self.prom_url = os.environ["PROMETHEUS_MCP_PROM_URL"].rstrip("/")
        # Alertmanager is optional. When unset, the alertmanager_* tools
        # surface a clear "not configured" error instead of crashing.
        self.am_url = os.environ.get("PROMETHEUS_MCP_AM_URL", "").rstrip("/") or None

    def resolve_bind_ip(self) -> str:
        if self.bind_ip != "auto":
            return self.bind_ip
        r = subprocess.run(
            ["tailscale", "ip", "-4"], capture_output=True, text=True, check=True
        )
        return r.stdout.strip().splitlines()[0]


def load_tokens(path: str) -> dict[str, str]:
    with open(path) as f:
        raw = json.load(f)
    tokens = raw.get("tokens", raw)
    if not isinstance(tokens, dict) or not tokens:
        raise SystemExit(f"{path}: expected non-empty token map")
    return {tok: client for client, tok in tokens.items()}


CFG: Config | None = None
TOKENS_BY_HEX: dict[str, str] = {}


# ── auth middleware ─────────────────────────────────────────────────────────

class BearerAuthMiddleware(BaseHTTPMiddleware):
    async def dispatch(self, request: Request, call_next):
        if request.url.path == "/health":
            return await call_next(request)
        auth = request.headers.get("authorization", "")
        if not auth.lower().startswith("bearer "):
            return JSONResponse({"error": "missing bearer token"}, status_code=401)
        token = auth.split(" ", 1)[1].strip()
        client = TOKENS_BY_HEX.get(token)
        if client is None:
            return JSONResponse({"error": "invalid token"}, status_code=401)
        request.state.client = client
        return await call_next(request)


# ── upstream clients ────────────────────────────────────────────────────────

async def _get_json(
    base: str, path: str, params: dict[str, Any] | None = None
) -> Any:
    """GET `base + path` with optional query params, return parsed JSON.
    Raises RuntimeError with a trimmed body on non-2xx. Token-free in
    the homelab today; if upstream auth gets added, the header
    construction lives here."""
    url = f"{base}/{path.lstrip('/')}"
    async with httpx.AsyncClient(timeout=15.0) as client:
        r = await client.get(url, params=params)
    if r.status_code >= 400:
        raise RuntimeError(f"GET {path} -> {r.status_code}: {r.text[:500]}")
    return r.json() if r.content else None


def _prom(path: str, params: dict[str, Any] | None = None):
    assert CFG is not None
    return _get_json(CFG.prom_url, path, params)


def _am(path: str, params: dict[str, Any] | None = None):
    assert CFG is not None
    if not CFG.am_url:
        raise RuntimeError(
            "alertmanager not configured — set PROMETHEUS_MCP_AM_URL"
        )
    return _get_json(CFG.am_url, path, params)


def _unwrap(resp: Any) -> Any:
    """Prometheus `/api/v1/*` wraps results in `{status, data}`. Surface
    `data` directly so callers don't have to dig. Errors bubble up via
    raised RuntimeError from the HTTP layer."""
    if isinstance(resp, dict) and resp.get("status") == "success":
        return resp.get("data")
    return resp


# ── MCP server ──────────────────────────────────────────────────────────────

mcp = FastMCP("prometheus")


@mcp.tool()
async def query(promql: str, time: str | None = None) -> Any:
    """Run an instant PromQL query against Prometheus.

    `promql`: the PromQL expression, e.g. `up`, `rate(http_requests_total[5m])`.
    `time`: optional evaluation timestamp (RFC3339 or unix seconds). Defaults
            to now.

    Returns Prometheus's `data` payload — a `{resultType, result}` shape where
    `result` is a list of `{metric, value: [ts, val]}` for vector/scalar
    queries or `{metric, values: [[ts, val], ...]}` for matrix."""
    params: dict[str, Any] = {"query": promql}
    if time is not None:
        params["time"] = time
    return _unwrap(await _prom("/api/v1/query", params))


@mcp.tool()
async def query_range(
    promql: str, start: str, end: str, step: str
) -> Any:
    """Run a PromQL range query and return a time-series matrix.

    `start`, `end`: RFC3339 timestamps or unix seconds.
    `step`: query resolution (e.g. `15s`, `1m`, `5m`). Smaller step = more
            points = slower. Match it to the dashboard granularity you'd want.

    Returns `{resultType: "matrix", result: [{metric, values: [[ts, val], ...]}]}`.
    Useful for trend questions: "show me CPU usage on saruman over the last
    hour" → query_range with rate(node_cpu_seconds_total{...}[1m]), start=-1h."""
    params = {"query": promql, "start": start, "end": end, "step": step}
    return _unwrap(await _prom("/api/v1/query_range", params))


@mcp.tool()
async def alerts() -> Any:
    """List currently active alerts as Prometheus sees them.

    Returns `{alerts: [{labels, annotations, state, activeAt, value}]}`. The
    `state` field is one of `pending`, `firing`. `pending` means the alert's
    condition just became true but `for:` hasn't elapsed yet — likely flapping
    or a brand-new incident. `firing` means it has held long enough to be
    routed to Alertmanager. Use `alertmanager_alerts()` for the Alertmanager
    view (which adds silencing/inhibition state)."""
    return _unwrap(await _prom("/api/v1/alerts"))


@mcp.tool()
async def rules(rule_type: str | None = None) -> Any:
    """List configured alerting and recording rules grouped by file.

    `rule_type`: optional filter — `alert` or `record`. Default = both.

    Returns `{groups: [{name, file, rules: [{name, query, ...}]}]}`.
    Useful for answering "what would page me right now?" or sanity-checking
    rule definitions live in Prometheus."""
    params = {"type": rule_type} if rule_type else None
    return _unwrap(await _prom("/api/v1/rules", params))


@mcp.tool()
async def targets(state: str | None = None) -> Any:
    """List scrape targets and their last-scrape status.

    `state`: optional filter — `active`, `dropped`, or `any` (default `any`).
            `dropped` shows targets that matched `relabel_configs` action=drop;
            these aren't broken, they're intentionally excluded.

    For each `activeTargets[*]`, key fields: `health` (up|down|unknown),
    `lastError` (scrape-error string when down), `lastScrape` timestamp,
    `scrapeUrl`, `labels` (the post-relabel target identity).

    Primary use: "is anything down right now?" → check `health=down` items."""
    params = {"state": state} if state else None
    return _unwrap(await _prom("/api/v1/targets", params))


@mcp.tool()
async def label_names(start: str | None = None, end: str | None = None) -> Any:
    """List every label name Prometheus knows about, optionally restricted
    to a time window. Useful as a discovery step before `label_values` or
    when constructing a query and you're not sure what labels the metric
    carries."""
    params: dict[str, Any] = {}
    if start is not None:
        params["start"] = start
    if end is not None:
        params["end"] = end
    return _unwrap(await _prom("/api/v1/labels", params or None))


@mcp.tool()
async def label_values(
    label: str, start: str | None = None, end: str | None = None
) -> Any:
    """List all values seen for a given label.

    Example: `label_values("job")` returns every scrape-job slug
    (`node`, `traefik`, `blocky`, …) — the most useful first call when
    exploring a new Prometheus."""
    params: dict[str, Any] = {}
    if start is not None:
        params["start"] = start
    if end is not None:
        params["end"] = end
    return _unwrap(
        await _prom(f"/api/v1/label/{label}/values", params or None)
    )


@mcp.tool()
async def series(
    selectors: list[str],
    start: str | None = None,
    end: str | None = None,
) -> Any:
    """Find time series matching one or more label selectors.

    `selectors`: list of selector strings like `up{job="node"}` or
                 `node_cpu_seconds_total{instance="saruman:9100"}`.

    Returns the matched series as `[{__name__, label1: ..., label2: ...}]`.
    Use to enumerate "which instances are scraping `up`?" or
    "what `node_filesystem_*` series exist?"."""
    params: dict[str, Any] = {"match[]": selectors}
    if start is not None:
        params["start"] = start
    if end is not None:
        params["end"] = end
    return _unwrap(await _prom("/api/v1/series", params))


@mcp.tool()
async def metric_metadata(
    metric: str | None = None, limit: int | None = None
) -> Any:
    """Fetch HELP text and TYPE for metrics. With no args, returns every
    metric's metadata (can be large — use `limit`). With `metric`, returns
    only that metric's entries.

    Returned shape: `{<metric>: [{type, help, unit}]}` (a list because the
    same metric name can appear in multiple targets with different help)."""
    params: dict[str, Any] = {}
    if metric is not None:
        params["metric"] = metric
    if limit is not None:
        params["limit"] = limit
    return _unwrap(await _prom("/api/v1/metadata", params or None))


@mcp.tool()
async def runtime_info() -> Any:
    """Prometheus's own runtime + build info: version, storage retention,
    chunk count, WAL stats. Cheap call; useful for "is the Prometheus
    server itself healthy?" probes."""
    runtime = _unwrap(await _prom("/api/v1/status/runtimeinfo"))
    build = _unwrap(await _prom("/api/v1/status/buildinfo"))
    flags = _unwrap(await _prom("/api/v1/status/flags"))
    return {"runtime": runtime, "build": build, "flags": flags}


# ── Alertmanager tools (gated on AM_URL being set) ──────────────────────────

@mcp.tool()
async def alertmanager_alerts(
    active: bool = True, silenced: bool = False, inhibited: bool = False
) -> Any:
    """Alerts as Alertmanager sees them — includes silence + inhibition state
    that Prometheus's own `/alerts` endpoint doesn't surface.

    By default returns only currently-firing, non-silenced, non-inhibited
    alerts. Toggle flags to see the others. Empty list = nothing actionable
    right now."""
    params = {
        "active": "true" if active else "false",
        "silenced": "true" if silenced else "false",
        "inhibited": "true" if inhibited else "false",
    }
    return await _am("/api/v2/alerts", params)


@mcp.tool()
async def alertmanager_silences() -> Any:
    """List active silences (alert-suppression windows). Useful before paging
    on something — confirm it isn't already known/silenced."""
    return await _am("/api/v2/silences")


# ── server bootstrap (matches miniflux-mcp / vault-mcp pattern) ─────────────

async def health(_request: Request) -> JSONResponse:
    return JSONResponse({"ok": True, "version": __version__})


async def version_route(_request: Request) -> JSONResponse:
    return JSONResponse({"version": __version__})


@asynccontextmanager
async def lifespan(_app: Starlette):
    async with mcp.session_manager.run():
        log.info(
            "prometheus-mcp ready (prom=%s, am=%s)",
            CFG.prom_url if CFG else "?",
            CFG.am_url if CFG and CFG.am_url else "<disabled>",
        )
        yield


def build_app() -> Starlette:
    mcp_app = mcp.streamable_http_app()
    return Starlette(
        debug=False,
        routes=[
            Route("/health", health, methods=["GET"]),
            Route("/version", version_route, methods=["GET"]),
            Mount("/", app=mcp_app),
        ],
        middleware=[Middleware(BearerAuthMiddleware)],
        lifespan=lifespan,
    )


def main() -> None:
    if "--version" in sys.argv[1:]:
        print(f"prometheus-mcp {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("PROMETHEUS_MCP_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting prometheus-mcp version %s on %s:%d (prom=%s, am=%s) with %d client tokens",
        __version__, bind_ip, CFG.port, CFG.prom_url,
        CFG.am_url or "<disabled>", len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
