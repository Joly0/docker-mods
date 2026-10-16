# syntax=docker/dockerfile:1

# Stage 1: Debian's gamescope with the Remote Play changes
FROM debian:trixie AS gamescope
COPY build/ /build-src/
RUN /build-src/gamescope.sh

# Stage 2: assemble the mod's files in one tree
FROM debian:trixie AS rootfs
COPY root/ /rootfs/
COPY --from=gamescope /out/ /rootfs/

# Stage 3: the mod itself. A single COPY, so the image has a single layer:
# the docker-mods installer in the base image applies only one layer.
FROM scratch

LABEL maintainer="Joly0"

COPY --from=rootfs /rootfs/ /
