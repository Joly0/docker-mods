# syntax=docker/dockerfile:1

# Stage 1: assemble the mod's files in one tree, with uv to install the MCP
# server (and a Python, should the image lack a recent one) at container start
FROM ghcr.io/astral-sh/uv:latest AS uv

FROM scratch AS rootfs
# Modes set here: s6 runs the run scripts directly, whatever git recorded.
COPY --chmod=755 root/ /
COPY --from=uv --chmod=755 /uv /usr/local/share/orcaslicer-mcp/uv

# Stage 2: the mod itself. A single COPY, so the image has a single layer:
# the docker-mods installer in the base image applies only one layer.
FROM scratch

LABEL maintainer="Joly0"

COPY --from=rootfs / /
