# syntax=docker/dockerfile:1

## Buildstage ##
FROM ghcr.io/linuxserver/baseimage-alpine:3.20 as buildstage-x86_64

ARG MOD_VERSION

RUN \
  echo "**** install packages ****" && \
  apk add -U --update --no-cache --virtual=build-dependencies \
    autoconf \
    automake \
    build-base && \
  echo "**** install par2cmdline-turbo from source ****" && \
  mkdir /tmp/par2cmdline && \
  curl -o \
    /tmp/par2cmdline.tar.gz -L \
    "https://github.com/animetosho/par2cmdline-turbo/archive/${MOD_VERSION}.tar.gz" && \
  tar xf \
    /tmp/par2cmdline.tar.gz -C \
    /tmp/par2cmdline --strip-components=1

## Buildstage ##
FROM --platform=aarch64 ghcr.io/linuxserver/baseimage-alpine:arm64v8-3.20 as buildstage-aarch64

ARG MOD_VERSION

RUN \
  echo "**** install packages ****" && \
  apk add -U --update --no-cache --virtual=build-dependencies \
    autoconf \
    automake \
    build-base \
    linux-headers && \
  echo "**** install par2cmdline-turbo from source ****" && \
  mkdir /tmp/par2cmdline && \
  curl -o \
    /tmp/par2cmdline.tar.gz -L \
    "https://github.com/animetosho/par2cmdline-turbo/archive/${MOD_VERSION}.tar.gz" && \
  tar xf \
    /tmp/par2cmdline.tar.gz -C \
    /tmp/par2cmdline --strip-components=1

FROM scratch as consolidate-builds

COPY root/ /

## Single layer deployed image ##
FROM scratch

LABEL maintainer="thespad"

# Add files from buildstage
COPY --from=consolidate-builds / /
