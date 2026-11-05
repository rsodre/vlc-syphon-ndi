#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Downloads the official universal VLC for macOS, checks it against VideoLAN's
# published SHA-256 and VideoLAN's Developer ID signature, and extracts VLC.app.
#
# Usage: apps/scripts/fetch-vlc-app.sh [version]       (default 3.0.24)
# Output: build/vlc-dist/<version>/VLC.app

set -euo pipefail

VERSION="${1:-3.0.24}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/vlc-dist/$VERSION"
DMG="$OUT/vlc-$VERSION-universal.dmg"
URL="https://download.videolan.org/pub/videolan/vlc/$VERSION/macosx/vlc-$VERSION-universal.dmg"
VIDEOLAN_TEAM="75GAHG3SZQ"

mkdir -p "$OUT"
if [[ -d "$OUT/VLC.app" ]]; then
  echo "$OUT/VLC.app already extracted"
  exit 0
fi
[[ -f "$DMG" ]] || { echo "Downloading $URL"; curl -fSL -o "$DMG" "$URL"; }

expected="$(curl -fsSL "$URL.sha256" | awk '{print $1}')"
actual="$(shasum -a 256 "$DMG" | awk '{print $1}')"
[[ "$expected" == "$actual" ]] || { echo "SHA-256 mismatch: expected $expected, got $actual" >&2; exit 1; }
echo "SHA-256 OK ($actual)"

mnt="$(mktemp -d)"
hdiutil attach -nobrowse -readonly -mountpoint "$mnt" "$DMG" >/dev/null
trap 'hdiutil detach "$mnt" >/dev/null 2>&1 || true' EXIT
codesign --verify --deep --strict "$mnt/VLC.app"
team="$(codesign -dv "$mnt/VLC.app" 2>&1 | sed -n 's/^TeamIdentifier=//p')"
[[ "$team" == "$VIDEOLAN_TEAM" ]] || { echo "Unexpected signer: $team" >&2; exit 1; }
echo "Signature OK (VideoLAN, $team)"
ditto "$mnt/VLC.app" "$OUT/VLC.app"
echo "Extracted $OUT/VLC.app"
