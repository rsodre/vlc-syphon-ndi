#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Builds everything for a macOS release into dist/<vlc version>-<build>/:
#   VLCSyphon-<v>.dmg, VLCNDI-<v>.dmg, vlc-syphon-ndi-plugins-macos-<v>.zip,
#   vlc-<vlc version>.tar.xz (VLC's source, for the GPL), SHA256SUMS
#
# Usage: apps/scripts/release-macos.sh <build-number>
# Environment:
#   SIGN_IDENTITY   "Developer ID Application: <name> (<team>)"; default "-" (ad-hoc, not
#                   distributable, notarization skipped)
#   NOTARY_PROFILE  notarytool keychain profile; required when SIGN_IDENTITY is set
#   VLC_VERSION     default 3.0.24

set -euo pipefail
BUILD_NUMBER="${1:?usage: release-macos.sh <build-number>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export VLC_VERSION="${VLC_VERSION:-3.0.24}"
export SIGN_IDENTITY="${SIGN_IDENTITY:--}"
V="$VLC_VERSION-$BUILD_NUMBER"
OUT="$ROOT/dist/$V"
S="$ROOT/apps/scripts"

notarize() { [[ "$SIGN_IDENTITY" == "-" ]] || "$S/notarize.sh" "$1"; }
if [[ "$SIGN_IDENTITY" != "-" ]]; then : "${NOTARY_PROFILE:?Set NOTARY_PROFILE}"; fi

cmake --preset macos >/dev/null
cmake --build --preset macos
"$S/package-macos.sh" "$BUILD_NUMBER"

for app in VLCSyphon VLCNDI; do
  notarize "$OUT/$app.app"
  "$S/make-dmg.sh" "$OUT/$app.app" "$OUT/$app-$V.dmg" "$app $V"
  notarize "$OUT/$app-$V.dmg"
done

"$S/package-plugins-macos.sh" "$OUT/vlc-syphon-ndi-plugins-macos-$V.zip"
notarize "$OUT/vlc-syphon-ndi-plugins-macos-$V.zip"

# VLC's source, offered next to the binaries (GPL).
src="$ROOT/build/vlc-dist/$VLC_VERSION/vlc-$VLC_VERSION.tar.xz"
[[ -f "$src" ]] || curl -fsSL -o "$src" "https://download.videolan.org/pub/videolan/vlc/$VLC_VERSION/vlc-$VLC_VERSION.tar.xz"
cp "$src" "$OUT/"

(cd "$OUT" && shasum -a 256 ./*.dmg ./*.zip ./*.tar.xz | sed 's| \./| |' > SHA256SUMS)
echo "Release files in $OUT:"
ls -lh "$OUT" | grep -v "\.app$"
