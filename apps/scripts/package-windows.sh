#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Builds the VLCNDI folder for Windows from the official VLC win64 zip (unmodified):
#   - adds the NDI plugin (plugins\video_filter\libndi_plugin.dll)
#   - adds the launcher VLCNDI.exe (apps/launcher) and VLCNDI-defaults.vlcrc, the settings
#     it copies to portable\vlcrc on first launch (from apps/VLCNDI/app.conf)
#   - adds SOURCE.txt
# The folder is portable: unzip anywhere writable and run VLCNDI.exe. Nothing is signed
# (there is no Windows code-signing certificate), so SmartScreen warns on first run.
#
# Runs in Git Bash / MSYS2 on Windows, or on Linux/macOS after a cross build.
#
# Usage: apps/scripts/package-windows.sh [build-number]           (default 1)
# Environment:
#   VLC_VERSION     default 3.0.24
#   BUILD_DIR       plugins build, default build/windows-mingw
# Output: dist/<version>-<build>/VLCNDI/

set -euo pipefail

BUILD_NUMBER="${1:-1}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VLC_VERSION="${VLC_VERSION:-3.0.24}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/windows-mingw}"
SRC="$ROOT/build/vlc-dist/$VLC_VERSION/win64/vlc-$VLC_VERSION"
OUT="$ROOT/dist/$VLC_VERSION-$BUILD_NUMBER"

DEFAULT_VIDEO_FILTER="" DEFAULT_AUDIO_FILTER="" WINDOWS_CORE_OPTIONS=()
# shellcheck disable=SC1091
source "$ROOT/apps/VLCNDI/app.conf"
app="$OUT/$APP_NAME"

for f in out/plugins/libndi_plugin.dll "out/apps/$APP_NAME.exe"; do
  [[ -f "$BUILD_DIR/$f" ]] || {
    echo "Missing $BUILD_DIR/$f. Build first: cmake --preset windows-mingw && cmake --build --preset windows-mingw" >&2; exit 1; }
done
[[ -f "$SRC/vlc.exe" ]] || "$ROOT/apps/scripts/fetch-vlc-win64.sh" "$VLC_VERSION"

echo "=== $APP_NAME (Windows)"
rm -rf "$app"
mkdir -p "$OUT"
cp -R "$SRC" "$app"

cp "$BUILD_DIR/out/plugins/libndi_plugin.dll" "$app/plugins/video_filter/"
cp "$BUILD_DIR/out/apps/$APP_NAME.exe" "$app/"

# First-launch settings, copied to portable\vlcrc by the launcher. VLC finds options by
# name, so they can all go under [core]; VLC moves them to their sections when it saves.
{
  printf '###\n### Created by %s on first launch: VLC'"'"'s defaults plus this app'"'"'s\n' "$APP_NAME"
  printf '### defaults. VLC rewrites this file when preferences are saved.\n###\n\n[core] # core program\n'
  for o in "${WINDOWS_CORE_OPTIONS[@]}"; do printf '%s\n' "$o"; done
  [[ -z "$DEFAULT_VIDEO_FILTER" ]] || printf 'video-filter=%s\n' "$DEFAULT_VIDEO_FILTER"
  [[ -z "$DEFAULT_AUDIO_FILTER" ]] || printf 'audio-filter=%s\n' "$DEFAULT_AUDIO_FILTER"
} > "$app/$APP_NAME-defaults.vlcrc"

# Where to get the source (GPL): VLC's tarball and this repository.
cat > "$app/SOURCE.txt" <<TXT
$APP_NAME $VLC_VERSION-$BUILD_NUMBER is the official VLC media player $VLC_VERSION for Windows (64-bit)
by VideoLAN, unmodified, with the vlc-syphon-ndi NDI plugin and a small launcher added
($APP_NAME.exe, $APP_NAME-defaults.vlcrc, plugins\\video_filter\\libndi_plugin.dll).

Start it with $APP_NAME.exe. Settings are kept in the "portable" folder next to it.
NDI needs the NDI 6 Runtime: http://ndi.link/NDIRedistV6

VLC source:      https://download.videolan.org/pub/videolan/vlc/$VLC_VERSION/
                 (also attached to the GitHub release of this app)
Plugins source:  https://github.com/rsodre/vlc-syphon-ndi

VLC is distributed under the GNU GPL v2 or later. The plugins are LGPL-2.1-or-later.
VLC and the VLC cone are trademarks of VideoLAN. This app is not made or endorsed by VideoLAN.
TXT

echo "$app"
