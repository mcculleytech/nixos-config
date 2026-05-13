"""Escalator MCP server.

Exposes a single tool, `consult_expert`, that one-shots a question against
a frontier model (default Anthropic Claude Opus 4.7 Fast) via OpenRouter
and returns the answer as plain text. Lets a cheap orchestrator agent
delegate hard sub-questions without permanently switching models.

Defense in depth: tailnet-only binding, bearer-token auth at the MCP
layer, hard cap on output tokens to bound spend per call.
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
    __version__ = _pkg_version("escalator-mcp")
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

log = logging.getLogger("escalator_mcp")


class Config:
    def __init__(self) -> None:
        self.bind_ip = os.environ.get("ESCALATOR_MCP_BIND_IP", "auto")
        self.port = int(os.environ.get("ESCALATOR_MCP_PORT", "4285"))
        self.tokens_file = os.environ["ESCALATOR_MCP_TOKENS_FILE"]
        self.openrouter_key = os.environ["OPENROUTER_API_KEY"]
        self.expert_model = os.environ.get(
            "ESCALATOR_MCP_EXPERT_MODEL", "anthropic/claude-opus-4.7-fast"
        )
        # Comma-separated whitelist of model slugs the orchestrator may
        # pass in `consult_expert(model=...)`. Anything outside this set
        # falls back to ESCALATOR_MCP_EXPERT_MODEL. Prevents the agent
        # from invoking arbitrary expensive models.
        allowed = os.environ.get(
            "ESCALATOR_MCP_ALLOWED_MODELS",
            ",".join([
                "anthropic/claude-opus-4.7-fast",
                "deepseek/deepseek-v4-pro",
                "google/gemini-3.1-pro-preview",
            ]),
        )
        self.allowed_models = {m.strip() for m in allowed.split(",") if m.strip()}
        self.max_output_tokens = int(
            os.environ.get("ESCALATOR_MCP_MAX_OUTPUT_TOKENS", "4096")
        )
        self.timeout_seconds = float(
            os.environ.get("ESCALATOR_MCP_TIMEOUT_SECONDS", "90")
        )

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


# ── auth middleware ──────────────────────────────────────────────────────────

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


# ── MCP server + tools ───────────────────────────────────────────────────────

mcp = FastMCP("escalator")


@mcp.tool()
async def consult_expert(
    question: str,
    model: str | None = None,
    context: str | None = None,
) -> dict[str, Any]:
    """Ask a frontier expert model a hard sub-question.

    Sends `question` (plus optional `context`) as a single-turn chat to
    the chosen expert model via OpenRouter. Returns the full text
    response. Each call is stateless — the expert sees no conversation
    history beyond the `question` + `context` you pass.

    Use this when alex explicitly asks to escalate ("use Opus for
    this", "what would DeepSeek say", "this needs more thought") OR
    when you (a cheap orchestrator) genuinely can't handle a
    subproblem. The expert answer becomes a tool result you can relay
    or summarize back to alex.

    Args:
      question: The exact question or task to give the expert. Be
        self-contained.
      model: Optional model slug to use. If alex says "use Opus" pass
        "anthropic/claude-opus-4.7-fast". If alex says "use DeepSeek"
        pass "deepseek/deepseek-v4-pro". For "what would Gemini Pro
        say" pass "google/gemini-3.1-pro-preview". Anything outside
        the configured allow-list falls back to the default expert
        (Opus). Omit to use the default.
      context: Optional supporting context (existing notes, code,
        constraints). Concatenated before the question.

    Returns: `{"model": <slug>, "answer": <text>, "usage": {input, output}}`.
    """
    assert CFG is not None
    parts: list[str] = []
    if context:
        parts.append(context.strip())
    parts.append(question.strip())
    user_message = "\n\n".join(parts)

    chosen_model = CFG.expert_model
    if model and model.strip() in CFG.allowed_models:
        chosen_model = model.strip()
    elif model and model.strip() not in CFG.allowed_models:
        log.info(
            "consult_expert: requested model %r not in allow-list; "
            "falling back to default %r",
            model,
            CFG.expert_model,
        )

    body = {
        "model": chosen_model,
        "max_tokens": CFG.max_output_tokens,
        "messages": [{"role": "user", "content": user_message}],
    }
    headers = {
        "Authorization": f"Bearer {CFG.openrouter_key}",
        "Content-Type": "application/json",
        # OR uses these for usage attribution; not required but polite.
        "HTTP-Referer": "https://hermes-agent.local/escalator-mcp",
        "X-Title": "escalator-mcp consult_expert",
    }
    try:
        async with httpx.AsyncClient(timeout=CFG.timeout_seconds) as client:
            r = await client.post(
                "https://openrouter.ai/api/v1/chat/completions",
                headers=headers,
                json=body,
            )
    except httpx.HTTPError as e:
        return {"error": f"openrouter request failed: {e!r}"}

    if r.status_code != 200:
        return {
            "error": f"openrouter HTTP {r.status_code}",
            "detail": r.text[:500],
        }

    payload = r.json()
    try:
        answer = payload["choices"][0]["message"]["content"]
    except (KeyError, IndexError, TypeError):
        return {"error": "malformed openrouter response", "raw": payload}

    usage = payload.get("usage", {})
    return {
        "model": payload.get("model", chosen_model),
        "answer": answer,
        "usage": {
            "input": usage.get("prompt_tokens", 0),
            "output": usage.get("completion_tokens", 0),
        },
    }


# ── /version + /health ───────────────────────────────────────────────────────

async def version_route(_request: Request) -> JSONResponse:
    return JSONResponse({"name": "escalator-mcp", "version": __version__})


async def health(_request: Request) -> JSONResponse:
    assert CFG is not None
    return JSONResponse({
        "status": "ok",
        "expert_model": CFG.expert_model,
        "max_output_tokens": CFG.max_output_tokens,
    })


# ── lifespan + main ──────────────────────────────────────────────────────────

@asynccontextmanager
async def lifespan(_app: Starlette):
    async with mcp.session_manager.run():
        log.info(
            "escalator-mcp ready; expert_model=%s",
            CFG.expert_model if CFG else "?",
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
        print(f"escalator-mcp {__version__}")
        return
    logging.basicConfig(
        level=os.environ.get("ESCALATOR_MCP_LOG_LEVEL", "INFO"),
        format="%(asctime)s %(levelname)s %(name)s: %(message)s",
    )
    global CFG, TOKENS_BY_HEX
    CFG = Config()
    TOKENS_BY_HEX = load_tokens(CFG.tokens_file)
    bind_ip = CFG.resolve_bind_ip()
    log.info(
        "starting escalator-mcp version %s on %s:%d (expert=%s) with %d client tokens",
        __version__,
        bind_ip,
        CFG.port,
        CFG.expert_model,
        len(TOKENS_BY_HEX),
    )
    uvicorn.run(build_app(), host=bind_ip, port=CFG.port, log_level="info")


if __name__ == "__main__":
    sys.exit(main())
