#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Smoke test: plays a short generated clip through an installed VLC with one of our
# video filters, without touching the VLC bundle (plugins are found via VLC_PLUGIN_PATH),
# and checks the filter's log lines.
#
# Usage: scripts/test-load-macos.sh [filter] [extra VLC args...]
#   filter   module name, default "hello"
# Environment:
#   VLC_APP      default /Applications/VLC.app
#   BUILD_DIR    default build/macos
#   PLUGIN_DIR   default $BUILD_DIR/out/plugins; set to "" to rely on plugins inside VLC.app

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILTER="${1:-hello}"; shift || true
VLC_APP="${VLC_APP:-/Applications/VLC.app}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/macos}"
PLUGIN_DIR="${PLUGIN_DIR-$BUILD_DIR/out/plugins}"
CLIP="$BUILD_DIR/test/testsrc.mp4"

if [[ ! -f "$CLIP" ]]; then
  command -v ffmpeg >/dev/null || { echo "ffmpeg is needed to generate the test clip" >&2; exit 1; }
  mkdir -p "$(dirname "$CLIP")"
  ffmpeg -loglevel error -f lavfi -i testsrc2=size=1280x720:rate=30 -t 2 \
         -c:v libx264 -pix_fmt yuv420p "$CLIP"
fi

LOG="$BUILD_DIR/test/vlc-$FILTER.log"
env ${PLUGIN_DIR:+VLC_PLUGIN_PATH="$PLUGIN_DIR"} \
  "$VLC_APP/Contents/MacOS/VLC" -I dummy --vout dummy --aout dummy --no-video-title-show \
  --video-filter="$FILTER" --play-and-exit -vv "$@" "$CLIP" >"$LOG" 2>&1 || true

grep -i "$FILTER" "$LOG" | grep -v "^\[.*\] main" || true
if grep -q "filter $FILTER.*\(hello from\|first frame\)\|\] $FILTER filter" "$LOG"; then
  echo "PASS: '$FILTER' loaded and processed frames ($LOG)"
else
  echo "FAIL: '$FILTER' did not run, see $LOG" >&2
  exit 1
fi
