# syntax=docker/dockerfile:1

# Stage 1: Debian's gamescope with the upstream Remote Play fixes
FROM debian:trixie AS gamescope
COPY build/ /build-src/
RUN /build-src/gamescope.sh

# Stage 2: the mod itself
FROM scratch

LABEL maintainer="Joly0"

# copy local files
COPY root/ /
COPY --from=gamescope /out/ /
