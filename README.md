# OrcaSlicer MCP - Docker mod for orcaslicer

This mod turns [linuxserver/orcaslicer](https://github.com/linuxserver/docker-orcaslicer)
into an OrcaSlicer an AI assistant can work with through
[orcaslicer-mcp](https://github.com/MaxEllis/orcaslicer-mcp): load models,
change settings, slice and read the result back, while you watch the same
OrcaSlicer in the browser.

Stock OrcaSlicer has no control API, so the mod replaces it with the
[OrcaSlicer MCP build](https://github.com/MaxEllis/OrcaSlicer/releases) (the
same OrcaSlicer plus a token-protected local API), switches that API on, and
runs the MCP server inside the container, reachable over HTTP.

## Usage

Set this environment variable on the orcaslicer container and map the MCP
server's port:

```
DOCKER_MODS=ghcr.io/joly0/docker-mods:orcaslicer-mcp
-p 13131:13131
```

Several mods are separated with `|`, e.g.
`linuxserver/mods:universal-package-install|ghcr.io/joly0/docker-mods:orcaslicer-mcp`.

On the first start the mod downloads the OrcaSlicer MCP build (about 140 MB)
and the MCP server; later starts reuse them from `/config/.cache/orcaslicer-mcp`.
On a slow connection the first start can take several minutes; restarting the
container meanwhile does not lose the download, it continues where it stopped.

1. **First start with a new `/config` only:** finish OrcaSlicer's setup wizard
   in the browser, then restart the container. OrcaSlicer writes its config
   during the wizard and the mod enables the API from the next start.
2. Get the MCP server's bearer token from
   `/config/.config/orcaslicer-mcp/server-token` (on Unraid e.g.
   `/mnt/user/appdata/orcaslicer/.config/orcaslicer-mcp/server-token`), or set
   your own with `ORCA_MCP_SERVER_TOKEN`.
3. Connect your MCP client to `http://<server-ip>:13131/mcp` with the header
   `Authorization: Bearer <token>`.

   **Claude Code:**
   ```
   claude mcp add --transport http orcaslicer http://<server-ip>:13131/mcp \
     --header "Authorization: Bearer <token>"
   ```
   or in a project's `.mcp.json`:
   ```json
   {
     "mcpServers": {
       "orcaslicer": {
         "type": "http",
         "url": "http://<server-ip>:13131/mcp",
         "headers": { "Authorization": "Bearer <token>" }
       }
     }
   }
   ```
   Other clients that support streamable HTTP servers take the same URL and
   header.

The OrcaSlicer API token is read from OrcaSlicer's config on every request,
so the MCP server needs no further setup, and regenerating the token in
**Preferences > Remote API** takes effect without a restart.

### Optional variables

| Variable | Default | Meaning |
|---|---|---|
| `ORCA_MCP_VERSION` | `latest` | Release tag of the [OrcaSlicer MCP build](https://github.com/MaxEllis/OrcaSlicer/releases), e.g. `v2.4.2-mcp.13`. `latest` checks for a new release at every start. |
| `ORCA_MCP_SERVER` | `true` | `false`: do not run the MCP server in the container (e.g. when you run `uvx orcaslicer-mcp` on your PC, see below). |
| `ORCA_MCP_SERVER_PORT` | `13131` | Port of the MCP server in the container. |
| `ORCA_MCP_SERVER_TOKEN` | generated | Bearer token MCP clients must send. Without it the mod generates one and keeps it in `/config/.config/orcaslicer-mcp/server-token`. |
| `ORCA_MCP_SERVER_VERSION` | latest | Version of [orcaslicer-mcp](https://pypi.org/project/orcaslicer-mcp/) on PyPI, e.g. `0.1.17`. Without it the server is updated at every start. |
| `ORCA_API_TOKEN` | OrcaSlicer's | Sets the OrcaSlicer API token (32 hex characters, as OrcaSlicer generates). |
| `ORCA_API_PORT` | `13130` | Port of OrcaSlicer's API. |
| `ORCA_API_BIND_LAN` | unchanged | `true`: OrcaSlicer's API listens on all interfaces instead of localhost (the **Allow LAN access** checkbox). Only needed for an MCP server outside the container. |
| `GITHUB_TOKEN` | (unset) | Used for the GitHub release lookup, in case the anonymous rate limit is hit. |

orcaslicer-mcp's own variables, such as `ORCA_MCP_ALLOW_KEYS`,
`ORCA_PRINTER_URL` and `ORCA_PRINTER_API_KEY`, can be set on the container
and reach the MCP server unchanged. See the
[orcaslicer-mcp README](https://github.com/MaxEllis/orcaslicer-mcp#readme) for
what they do.

### MCP server on your PC instead

To run orcaslicer-mcp on the machine of your MCP client (stdio, via `uvx`)
instead of in the container, set `ORCA_MCP_SERVER=false`,
`ORCA_API_BIND_LAN=true` and map port `13130`, then follow the
[orcaslicer-mcp quickstart](https://github.com/MaxEllis/orcaslicer-mcp#quickstart)
with `ORCA_API_URL=http://<server-ip>:13130` and the token from OrcaSlicer's
**Preferences > Remote API** (or the one you set with `ORCA_API_TOKEN`).

## What it does at container start

- downloads the OrcaSlicer MCP build for the container's architecture (x64 or
  aarch64), checks it against the release's `SHA256SUMS.txt` and unpacks it
  into `/config/.cache/orcaslicer-mcp/app`, once per version; older versions
  are removed. A download cut short by a container stop or restart resumes at
  the next start instead of starting over
- points `/opt/orcaslicer`, which the image's autostart and menu start, at
  that build; the image's own OrcaSlicer stays in `/opt/orcaslicer-stock`
- if GitHub cannot be reached, uses the build already in `/config`, and the
  stock OrcaSlicer if there is none
- enables OrcaSlicer's Remote API in `/config/.config/OrcaSlicer/OrcaSlicer.conf`
  and applies `ORCA_API_PORT`, `ORCA_API_BIND_LAN` and `ORCA_API_TOKEN`
- installs orcaslicer-mcp with [uv](https://github.com/astral-sh/uv) (bundled
  in the mod) into `/config/.cache/orcaslicer-mcp/server`, using the image's
  Python, or a downloaded one if it has none recent enough
- runs the MCP server as a service on `ORCA_MCP_SERVER_PORT`, behind the bearer
  token

## Notes

- Update OrcaSlicer by restarting the container (with `ORCA_MCP_VERSION=latest`),
  never from inside the app: the in-app updater offers stock OrcaSlicer, which
  has no API. The MCP builds switch that updater off themselves.
- The MCP endpoint is plain HTTP with a bearer token. Keep it on your LAN and
  do not forward it to the internet. Anyone with the token can control the
  slicer; orcaslicer-mcp still refuses to change G-code templates,
  post-processing scripts and printer connection settings unless you allow
  them with `ORCA_MCP_ALLOW_KEYS`.
- The OrcaSlicer MCP build follows upstream OrcaSlicer with a delay, so it can
  be a version behind the image's stock OrcaSlicer. Both use the same profile
  folder.
- To go back to stock OrcaSlicer, remove the mod and recreate the container.
  `/config/.cache/orcaslicer-mcp` can then be deleted.
