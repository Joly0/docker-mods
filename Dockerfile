# syntax=docker/dockerfile:1

FROM scratch

LABEL maintainer="joly0"

# copy local files
COPY root/ /
