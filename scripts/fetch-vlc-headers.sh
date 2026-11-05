#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Vendors the VLC plugin headers for one release into third_party/vlc/<version>/.
# Downloads the official source tarball, checks it against VideoLAN's published
# SHA-256, and keeps only what out-of-tree plugins need:
#   include/            plugin + libvlc headers (libvlc_version.h generated)
#   libvlccore.sym      exported symbols, used to generate link stubs
#   COPYING.LIB         license of the headers
#
# Usage: scripts/fetch-vlc-headers.sh [version] [tarball]
#   version  defaults to 3.0.24
#   tarball  optional path to an already-downloaded vlc-<version>.tar.xz

set -euo pipefail

VERSION="${1:-3.0.24}"
TARBALL="${2:-}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DEST="$ROOT/third_party/vlc/$VERSION"
URL="https://download.videolan.org/pub/videolan/vlc/$VERSION/vlc-$VERSION.tar.xz"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if [[ -z "$TARBALL" ]]; then
  TARBALL="$WORK/vlc-$VERSION.tar.xz"
  echo "Downloading $URL"
  curl -fSL -o "$TARBALL" "$URL"
fi

EXPECTED="$(curl -fsSL "$URL.sha256" | awk '{print $1}')"
ACTUAL="$(shasum -a 256 "$TARBALL" | awk '{print $1}')"
if [[ "$EXPECTED" != "$ACTUAL" ]]; then
  echo "SHA-256 mismatch: expected $EXPECTED, got $ACTUAL" >&2
  exit 1
fi
echo "SHA-256 OK ($ACTUAL)"

tar -xJf "$TARBALL" -C "$WORK" \
  "vlc-$VERSION/include" \
  "vlc-$VERSION/src/libvlccore.sym" \
  "vlc-$VERSION/COPYING.LIB"

SRC="$WORK/vlc-$VERSION"
IFS=. read -r MAJOR MINOR REVISION EXTRA <<<"$VERSION"
EXTRA="${EXTRA:-0}"

sed -e "s/@VERSION_MAJOR@/$MAJOR/" \
    -e "s/@VERSION_MINOR@/$MINOR/" \
    -e "s/@VERSION_REVISION@/$REVISION/" \
    -e "s/@VERSION_EXTRA@/$EXTRA/" \
    "$SRC/include/vlc/libvlc_version.h.in" > "$SRC/include/vlc/libvlc_version.h"
rm "$SRC/include/vlc/libvlc_version.h.in"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -R "$SRC/include" "$DEST/"
cp "$SRC/src/libvlccore.sym" "$SRC/COPYING.LIB" "$DEST/"
printf '%s  vlc-%s.tar.xz\n' "$ACTUAL" "$VERSION" > "$DEST/SOURCE.sha256"

echo "Vendored VLC $VERSION headers into ${DEST#$ROOT/}"
