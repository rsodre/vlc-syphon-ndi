#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Zips the macOS plugins for people who use the official VLC:
#   plugins/libsyphon_plugin.dylib, plugins/libndi_plugin.dylib, plugins/Syphon.framework
#   INSTALL.txt
# The dylibs and framework are signed (hardened runtime) so the zip can be notarized.
#
# Usage: apps/scripts/package-plugins-macos.sh <out.zip>
# Environment: SIGN_IDENTITY (default "-"), BUILD_DIR (default build/macos)

set -euo pipefail
out="$1"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/macos}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
flags=(--force --sign "$SIGN_IDENTITY" --options runtime)
[[ "$SIGN_IDENTITY" != "-" ]] && flags+=(--timestamp)

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/plugins"
cp "$BUILD_DIR"/out/plugins/lib{syphon,ndi}_plugin.dylib "$stage/plugins/"
ditto "$ROOT/third_party/syphon/darwin/Syphon.framework" "$stage/plugins/Syphon.framework"
codesign "${flags[@]}" "$stage/plugins/Syphon.framework" "$stage"/plugins/*.dylib
cat > "$stage/INSTALL.txt" <<'TXT'
vlc-syphon-ndi plugins for VLC 3.0.x on macOS (11 or later). NDI needs macOS 13 and the
NDI Runtime, libNDI_for_Mac.pkg from http://ndi.link/NDIRedistV6Apple (NDI Tools alone is not enough).

Keep the three items in plugins/ together. Recommended: leave VLC.app untouched and
start VLC with the plugin folder:

  mkdir -p "$HOME/Library/Application Support/vlc-syphon-ndi"
  cp -R plugins "$HOME/Library/Application Support/vlc-syphon-ndi/"
  open --env VLC_PLUGIN_PATH="$HOME/Library/Application Support/vlc-syphon-ndi/plugins" -a VLC

Then enable the filters in Preferences > Show All > Video > Filters (Syphon, NDI) and
Audio > Filters (NDI), or: --video-filter=syphon:ndi --audio-filter=ndi

Instructions and the ready-made VLCSyphon/VLCNDI apps:
https://github.com/rsodre/vlc-syphon-ndi
TXT
rm -f "$out"
(cd "$stage" && ditto -c -k --norsrc --noextattr . "$out")
echo "$out"
