#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Builds everything for a Windows release into dist/<vlc version>-<build>/:
#   VLCNDI-<v>-win64.zip                       the portable app (folder VLCNDI\)
#   vlc-syphon-ndi-plugins-windows-<v>.zip     the NDI plugin for the official VLC
#   SHA256SUMS.windows                         checksums of the two zips
# VLC's source (vlc-<vlc version>.tar.xz) is the same file as in the macOS release.
#
# Runs in Git Bash / MSYS2 on Windows, or on Linux/macOS (cross build), with CMake, Ninja
# and MinGW-w64 in PATH. Nothing is signed.
#
# Usage: apps/scripts/release-windows.sh <build-number>
# Environment: VLC_VERSION (default 3.0.24)

set -euo pipefail
BUILD_NUMBER="${1:?usage: release-windows.sh <build-number>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
export VLC_VERSION="${VLC_VERSION:-3.0.24}"
V="$VLC_VERSION-$BUILD_NUMBER"
OUT="$ROOT/dist/$V"
BUILD_DIR="$ROOT/build/windows-mingw"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$@"; else shasum -a 256 "$@"; fi; }

(cd "$ROOT" && cmake --preset windows-mingw -DVSN_APP_BUILD="$BUILD_NUMBER" >/dev/null && cmake --build --preset windows-mingw)
"$ROOT/apps/scripts/package-windows.sh" "$BUILD_NUMBER"

app_zip="VLCNDI-$V-win64.zip"
plugins_zip="vlc-syphon-ndi-plugins-windows-$V.zip"
rm -f "$OUT/$app_zip" "$OUT/$plugins_zip"
(cd "$OUT" && cmake -E tar cf "$app_zip" --format=zip VLCNDI)

stage="$(mktemp -d)"
trap 'rm -rf "$stage"' EXIT
mkdir -p "$stage/plugins/video_filter"
cp "$BUILD_DIR/out/plugins/libndi_plugin.dll" "$stage/plugins/video_filter/"
cat > "$stage/INSTALL.txt" <<'TXT'
vlc-syphon-ndi NDI plugin for VLC 3.0.x on Windows (64-bit VLC, Windows 10 or later).
It needs only the NDI 6 Runtime from http://ndi.link/NDIRedistV6. NDI Tools is not needed.

1. Copy plugins\video_filter\libndi_plugin.dll into VLC's folder of the same name,
   usually C:\Program Files\VideoLAN\VLC\plugins\video_filter\ (needs administrator rights).
2. Refresh VLC's plugin list once, in a Command Prompt run as administrator:
     "C:\Program Files\VideoLAN\VLC\vlc-cache-gen.exe" "C:\Program Files\VideoLAN\VLC\plugins"
3. In VLC: Tools > Preferences > Show settings: All, then tick NDI under Video > Filters and
   Audio > Filters, Save, and restart VLC. Or start VLC with:
     --video-filter=ndi --audio-filter=ndi
   To keep the NDI source up while nothing plays, also tick NDI under Interface > Control
   interfaces (or --control=ndi).

A VLC update removes the plugin: copy it again. The 32-bit VLC is not supported.

Instructions and the ready-made VLCNDI app:
https://github.com/rsodre/vlc-syphon-ndi
TXT
(cd "$stage" && cmake -E tar cf "$OUT/$plugins_zip" --format=zip plugins INSTALL.txt)

(cd "$OUT" && sha256 "$app_zip" "$plugins_zip" | sed 's| \*|  |' > SHA256SUMS.windows)
echo "Release files in $OUT:"
ls -lh "$OUT/$app_zip" "$OUT/$plugins_zip" "$OUT/SHA256SUMS.windows"
cat "$OUT/SHA256SUMS.windows"
