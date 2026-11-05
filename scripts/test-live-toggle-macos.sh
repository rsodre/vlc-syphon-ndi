#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Live enable/disable test: while a video loops, scripts/lua/vsn_toggle.lua changes the
# saved filter settings the way Preferences does, and the probes check that the Syphon
# server / NDI source follow within a second (start, carry video, stop).
#
# Usage: scripts/test-live-toggle-macos.sh [syphon|ndi]...   (default: both)
# NDI needs the runtime: installed, or NDI_RUNTIME_DIR_V6.

set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VLC_APP="${VLC_APP:-/Applications/VLC.app}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/macos}"
TEST_DIR="$BUILD_DIR/test"
CLIP="$TEST_DIR/live-30s.mp4"
mkdir -p "$TEST_DIR"
[[ -f "$CLIP" ]] || ffmpeg -loglevel error -y -f lavfi -i "color=c=0xFF0000:s=1280x720:r=30,format=yuv420p" \
  -f lavfi -i "sine=frequency=1000:sample_rate=48000" -t 30 -c:v libx264 -colorspace bt709 -c:a aac -ac 2 "$CLIP"

# Probes must time out before the next switch point (they wait for a source to appear).
run() {  # plugin steps vlc-args... ; then pairs "time expectation" on stdin
  local plugin="$1" steps="$2"; shift 2
  local home; home="$(mktemp -d)"
  mkdir -p "$home/Library/Application Support/org.videolan.vlc/lua/intf"
  cp "$ROOT/scripts/lua/vsn_toggle.lua" "$home/Library/Application Support/org.videolan.vlc/lua/intf/"
  HOME="$home" VSN_TOGGLE="$steps" VLC_PLUGIN_PATH="$BUILD_DIR/out/plugins" "$VLC_APP/Contents/MacOS/VLC" \
    -I dummy --extraintf=luaintf --lua-intf=vsn_toggle --vout dummy --aout dummy --loop "$@" "$CLIP" \
    >"$TEST_DIR/live-$plugin.log" 2>&1 &
  local vlc_pid=$! start=$SECONDS fail=0
  while read -r at want; do
    while (( SECONDS - start < at )); do sleep 0.2; done
    local got
    if [[ $plugin == syphon ]]; then
      got="$("$BUILD_DIR/out/tools/syphon-probe" --server vsn-live --timeout 0.6 2>&1 | grep -q '^frame: 1280x720' && echo on || echo off)"
    else
      got="$("$BUILD_DIR/out/tools/ndi-probe" --source '(vsn-live)' --timeout 1.2 2>&1 | grep -q '^video: 1280x720' && echo on || echo off)"
    fi
    printf '  t=%-3s want %-3s got %s\n' "$at" "$want" "$got"
    [[ $got == "$want" ]] || fail=1
  done
  kill "$vlc_pid" 2>/dev/null || true; wait "$vlc_pid" 2>/dev/null || true
  rm -rf "$home"
  if (( fail )); then echo "FAIL ($plugin)"; return 1; fi
  echo "PASS ($plugin)"
}

status=0
for p in "${@:-syphon ndi}"; do for plugin in $p; do
  echo "--- $plugin: off, on at 4 s, off at 9 s, on at 14 s"
  case $plugin in
    syphon) run syphon "4:video-filter=syphon 9:video-filter= 14:video-filter=syphon" \
              --control=syphon --syphon-name=vsn-live <<<$'2 off\n7 on\n12 off\n17 on' || status=1 ;;
    ndi)    run ndi "4:video-filter=ndi 4:audio-filter=ndi 9:video-filter= 9:audio-filter= 14:video-filter=ndi" \
              --control=ndi --ndi-name=vsn-live <<<$'2 off\n7 on\n12 off\n17 on' || status=1 ;;
  esac
done; done
exit $status
