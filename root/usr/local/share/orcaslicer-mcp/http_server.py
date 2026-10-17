"""Serve orcaslicer-mcp over streamable HTTP with a bearer token.

orcaslicer-mcp itself only speaks stdio, which needs the MCP client and the
server on one machine. This runs the same server inside the container so any
MCP client on the network can reach it at http://<host>:<port>/mcp.

Environment (all optional):
  ORCA_MCP_SERVER_PORT   listen port, default 13131
  ORCA_MCP_SERVER_TOKEN  bearer token clients must send; default the token the
                         mod generated in /config/.config/orcaslicer-mcp/server-token
  ORCA_API_TOKEN         OrcaSlicer Remote API token; default read from
                         OrcaSlicer.conf on every request, so a token
                         regenerated in Preferences works without a restart
  ORCA_API_PORT          OrcaSlicer Remote API port, default from OrcaSlicer.conf
  Everything else orcaslicer-mcp reads (ORCA_MCP_ALLOW_KEYS, ORCA_PRINTER_URL,
  ...) passes through unchanged.
"""

import hmac
import json
import os
import sys
from pathlib import Path

import uvicorn
from mcp.server.transport_security import TransportSecuritySettings

from orcaslicer_mcp.server import allow_override_warnings, mcp

CONF = Path("/config/.config/OrcaSlicer/OrcaSlicer.conf")
TOKEN_FILE = Path("/config/.config/orcaslicer-mcp/server-token")


def log(msg: str) -> None:
    print(f"[orcaslicer-mcp] {msg}", file=sys.stderr, flush=True)


class OrcaConf:
    """Remote API settings from OrcaSlicer.conf, re-read when the file changes."""

    def __init__(self) -> None:
        self._mtime = None
        self._app: dict = {}

    def app(self) -> dict:
        try:
            mtime = CONF.stat().st_mtime_ns
            if mtime != self._mtime:
                self._app = json.loads(CONF.read_text()).get("app", {})
                self._mtime = mtime
        except (OSError, ValueError):
            pass
        return self._app


orca_conf = OrcaConf()
USER_API_TOKEN = os.environ.get("ORCA_API_TOKEN", "").strip()
USER_API_URL = os.environ.get("ORCA_API_URL", "").strip()


def refresh_orca_env() -> None:
    # orcaslicer-mcp reads ORCA_API_TOKEN / ORCA_API_URL on every tool call.
    app = orca_conf.app()
    token = USER_API_TOKEN or str(app.get("remote_api_token", ""))
    if token:
        os.environ["ORCA_API_TOKEN"] = token
    if not USER_API_URL:
        port = os.environ.get("ORCA_API_PORT") or app.get("remote_api_port") or "13130"
        os.environ["ORCA_API_URL"] = f"http://127.0.0.1:{port}"


class BearerAuth:
    """ASGI middleware: reject HTTP requests without the bearer token."""

    def __init__(self, app, token: str) -> None:
        self.app = app
        self.expected = f"Bearer {token}".encode()

    async def __call__(self, scope, receive, send):
        if scope["type"] == "http":
            auth = dict(scope.get("headers") or []).get(b"authorization", b"")
            if not hmac.compare_digest(auth, self.expected):
                await send({
                    "type": "http.response.start",
                    "status": 401,
                    "headers": [
                        (b"content-type", b"application/json"),
                        (b"www-authenticate", b'Bearer realm="orcaslicer-mcp"'),
                    ],
                })
                await send({"type": "http.response.body", "body": b'{"error":"unauthorized"}'})
                return
            refresh_orca_env()
        await self.app(scope, receive, send)


def main() -> None:
    token = os.environ.get("ORCA_MCP_SERVER_TOKEN", "").strip()
    if not token:
        try:
            token = TOKEN_FILE.read_text().strip()
        except OSError:
            pass
    if not token:
        log("no bearer token (ORCA_MCP_SERVER_TOKEN or %s), not starting" % TOKEN_FILE)
        sys.exit(1)

    port = int(os.environ.get("ORCA_MCP_SERVER_PORT", "13131"))
    for w in allow_override_warnings():
        log(w)
    refresh_orca_env()

    # The bearer token guards the endpoint; the Host check of the SDK would
    # only admit localhost, which a client on the network never is.
    app = mcp.streamable_http_app(
        host="0.0.0.0",
        transport_security=TransportSecuritySettings(enable_dns_rebinding_protection=False),
    )
    log(f"MCP server listening on port {port}, endpoint /mcp")
    uvicorn.run(BearerAuth(app, token), host="0.0.0.0", port=port, log_level="warning")


if __name__ == "__main__":
    main()
