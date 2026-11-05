#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Packs an app into a compressed DMG with an Applications shortcut and signs it.
#
# Usage: apps/scripts/make-dmg.sh <App.app> <out.dmg> [volume name]
# Environment: SIGN_IDENTITY (default "-": the DMG is left unsigned)

set -euo pipefail
app="$1" out="$2" vol="${3:-$(basename "$1" .app)}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/$(basename "$app")"
ln -s /Applications "$stage/Applications"
rm -f "$out"
hdiutil create -quiet -volname "$vol" -srcfolder "$stage" -fs HFS+ -format UDZO -imagekey zlib-level=9 "$out"
if [[ "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --sign "$SIGN_IDENTITY" --timestamp "$out"
fi
echo "$out"
