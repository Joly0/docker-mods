#!/bin/bash
# Build Debian's gamescope package with the upstream Remote Play fixes
# (ValveSoftware/gamescope #2271) for gamescope versions older than 3.16.31:
#   9851c606  screenshot/PipeWire textures must be sampled, otherwise the
#             RGB-to-NV12 shader reads nothing and the stream is black
#   ff6b924f  NVIDIA has no XRGB2101010 storage images: capture via
#             XBGR2101010, otherwise red and blue are swapped
# Plus one change of our own, gamescope-stream-overlays.patch: the PipeWire
# stream also carries the overlay layers the screen shows (mangoapp, Steam's
# overlay with its performance information, notifications); upstream streams
# only the game or Big Picture.
# Output: /out/usr/share/steam-remoteplay/gamescope_*.deb
set -euo pipefail
mkdir -p /out/usr/share/steam-remoteplay

sed -i -e 's/^Types: deb$/Types: deb deb-src/' \
       -e 's/^Components: main$/Components: main contrib/' /etc/apt/sources.list.d/debian.sources
cat > /etc/apt/sources.list.d/backports.sources <<SRC
Types: deb deb-src
URIs: http://deb.debian.org/debian
Suites: trixie-backports
Components: main contrib
Signed-By: /usr/share/keyrings/debian-archive-keyring.gpg
SRC
apt-get update -qq

version=$(apt-cache policy gamescope | awk '/Candidate:/{print $2}')
UPSTREAM_FIXED=""
if dpkg --compare-versions "${version%%+*}" ge 3.16.31; then
    UPSTREAM_FIXED=1
fi

export DEBIAN_FRONTEND=noninteractive
apt-get install -y -qq --no-install-recommends build-essential devscripts dpkg-dev fakeroot >/dev/null
apt-get build-dep -y -qq -t trixie-backports gamescope >/dev/null
mkdir -p /build && cd /build
apt-get source -qq -t trixie-backports gamescope
cd gamescope-*/

patch -p1 < /build-src/gamescope-stream-overlays.patch

if [ -z "$UPSTREAM_FIXED" ]; then
    sed -i 's|^\(\t\t\t\)screenshotImageFlags.bStorage = true;$|&\n\1screenshotImageFlags.bSampled = true;|' src/rendervulkan.cpp
    grep -q 'screenshotImageFlags.bSampled = true;' src/rendervulkan.cpp

    sed -i 's|vulkan_acquire_screenshot_texture( uWidth, uHeight, false, DRM_FORMAT_XRGB2101010 )|vulkan_acquire_screenshot_texture( uWidth, uHeight, false, DRM_FORMAT_XBGR2101010 )|' src/steamcompmgr.cpp
    grep -q 'uHeight, false, DRM_FORMAT_XBGR2101010' src/steamcompmgr.cpp
fi

# Bump REVISION whenever the changes to gamescope change, so containers
# replace an older patched build.
REVISION=2
DEBFULLNAME="steam-remoteplay" DEBEMAIL="noreply@localhost" \
    dch -v "${version}+remoteplay${REVISION}" "Steam Remote Play: stream overlay layers; backport PipeWire capture fixes (gamescope #2271)."
DEB_BUILD_OPTIONS="nocheck parallel=$(nproc)" dpkg-buildpackage -us -uc -b >/dev/null
cp /build/gamescope_*_amd64.deb /out/usr/share/steam-remoteplay/
ls -la /out/usr/share/steam-remoteplay/
