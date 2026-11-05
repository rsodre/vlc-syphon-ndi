#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# End-to-end test of the syphon plugin. For each case it plays a generated
# four-colour clip in the installed VLC (untouched, plugins via VLC_PLUGIN_PATH)
# with --video-filter=syphon, grabs a frame with tools/syphon-probe and checks
# the frame size and the colour at the centre of each quadrant:
#
#   red | green
#   ----+------
#   blue| grey 128
#
# Usage: scripts/test-syphon-macos.sh [case...]      (default: all cases)
# Environment: VLC_APP (default /Applications/VLC.app), BUILD_DIR (default build/macos)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VLC_APP="${VLC_APP:-/Applications/VLC.app}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/macos}"
PLUGIN_DIR="$BUILD_DIR/out/plugins"
PROBE="$BUILD_DIR/out/tools/syphon-probe"
TEST_DIR="$BUILD_DIR/test"
mkdir -p "$TEST_DIR"

[[ -x "$PROBE" && -f "$PLUGIN_DIR/libsyphon_plugin.dylib" ]] || {
  echo "Build first: cmake --preset macos && cmake --build --preset macos" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed to generate the test clips" >&2; exit 1; }

SW=(--codec=avcodec --avcodec-hw=none)

# name | storage WxH | ffmpeg filter tail | ffmpeg encoder args | VLC args | expected published WxH
CASES=(
  "hw-709|1280x720|scale=out_color_matrix=bt709:out_range=tv,format=yuv420p|-c:v libx264 -colorspace bt709 -color_range tv||1280x720"
  "sw-709|1280x720|scale=out_color_matrix=bt709:out_range=tv,format=yuv420p|-c:v libx264 -colorspace bt709 -color_range tv|${SW[*]}|1280x720"
  "hw-1080-crop|1920x1080|scale=out_color_matrix=bt709:out_range=tv,format=yuv420p|-c:v libx264 -colorspace bt709 -color_range tv||1920x1080"
  "hw-601-anamorphic|720x576|scale=out_color_matrix=bt601:out_range=tv,format=yuv420p,setsar=64/45|-c:v libx264 -colorspace smpte170m -color_range tv||1024x576"
  "sw-601-anamorphic|720x576|scale=out_color_matrix=bt601:out_range=tv,format=yuv420p,setsar=64/45|-c:v libx264 -colorspace smpte170m -color_range tv|${SW[*]}|1024x576"
  "hw-full-range|1280x720|scale=out_color_matrix=bt709:out_range=pc,format=yuvj420p|-c:v libx264 -colorspace bt709 -color_range pc||1280x720"
  "hw-hevc-10bit|1280x720|scale=out_color_matrix=bt709:out_range=tv,format=yuv420p10le|-c:v libx265 -x265-params log-level=error -tag:v hvc1 -colorspace bt709 -color_range tv||1280x720"
  "sw-422-converted|1280x720|scale=out_color_matrix=bt709:out_range=tv,format=yuv422p|-c:v libx264 -colorspace bt709 -color_range tv|${SW[*]}|1280x720"
)
EXPECT=("255 0 0" "0 255 0" "0 0 255" "128 128 128")
TOL=6

make_clip() {  # name size filter encoder-args
  local clip="$TEST_DIR/$1.mp4"
  [[ -f "$clip" ]] && { echo "$clip"; return; }
  local w=${2%x*} h=${2#*x}
  local q="s=$((w / 2))x$((h / 2)):r=30"
  # shellcheck disable=SC2086
  ffmpeg -loglevel error -y \
    -f lavfi -i "color=c=0xFF0000:$q" -f lavfi -i "color=c=0x00FF00:$q" \
    -f lavfi -i "color=c=0x0000FF:$q" -f lavfi -i "color=c=0x808080:$q" \
    -filter_complex "[0][1][2][3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,$3" \
    -t 3 $4 -color_primaries bt709 -color_trc bt709 "$clip"
  echo "$clip"
}

run_case() {
  IFS='|' read -r name size filter enc vlcargs want <<<"$1"
  local clip log="$TEST_DIR/vlc-syphon-$name.log" png="$TEST_DIR/syphon-$name.png"
  clip="$(make_clip "$name" "$size" "$filter" "$enc")"

  # shellcheck disable=SC2086
  VLC_PLUGIN_PATH="$PLUGIN_DIR" "$VLC_APP/Contents/MacOS/VLC" -I dummy --vout dummy --aout dummy \
    --no-video-title-show --video-filter=syphon --syphon-name="vsn-test-$name" --loop -vv \
    $vlcargs "$clip" >"$log" 2>&1 &
  local vlc_pid=$!

  local ww=${want%x*} wh=${want#*x}
  local points=("$((ww / 4)),$((wh / 4))" "$((ww * 3 / 4)),$((wh / 4))"
                "$((ww / 4)),$((wh * 3 / 4))" "$((ww * 3 / 4)),$((wh * 3 / 4))")
  local args=(--server "vsn-test-$name" --out "$png" --timeout 15)
  for p in "${points[@]}"; do args+=(--pixel "$p"); done
  local out rc=0
  out="$("$PROBE" "${args[@]}" 2>&1)" || rc=$?
  kill "$vlc_pid" 2>/dev/null || true
  wait "$vlc_pid" 2>/dev/null || true

  local chroma
  chroma="$(sed -n 's/.*Syphon filter on \([^ ]*\) .*/\1/p' "$log" | tail -1)"
  echo "--- $name (filter input: ${chroma:-?})"
  grep -E "^(frame|pixel)" <<<"$out" | sed 's/^/  /' || true
  grep -E "syphon.*(cannot|error)" "$log" | sed 's/^/  /' || true
  if [[ $rc -ne 0 ]]; then echo "FAIL ($name): $out (log: $log)"; return 1; fi
  grep -q "^frame: $want " <<<"$out" || { echo "FAIL ($name): expected $want"; return 1; }

  local i=0 fail=0
  while read -r r g b; do
    read -r er eg eb <<<"${EXPECT[$i]}"
    for pair in "$r:$er" "$g:$eg" "$b:$eb"; do
      local got=${pair%%:*} exp=${pair##*:}
      local d=$(( got > exp ? got - exp : exp - got ))
      (( d <= TOL )) || { echo "  pixel ${points[$i]}: got $r $g $b, want ${EXPECT[$i]}"; fail=1; break; }
    done
    i=$((i + 1))
  done < <(sed -n 's/^pixel .*: r=\([0-9]*\) g=\([0-9]*\) b=\([0-9]*\).*/\1 \2 \3/p' <<<"$out")
  (( i == 4 )) || fail=1
  if (( fail )); then echo "FAIL ($name): colours"; return 1; fi
  echo "PASS ($name)"
}

status=0
for c in "${CASES[@]}"; do
  name=${c%%|*}
  if (( $# )) && [[ ! " $* " == *" $name "* ]]; then continue; fi
  run_case "$c" || status=1
done
exit $status
