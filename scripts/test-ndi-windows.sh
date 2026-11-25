#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# End-to-end test of the ndi plugin on Windows (run in Git Bash or MSYS2). Plays generated
# clips in a copy of the official VLC (with the plugin copied in) with the NDI video and
# audio filters, receives them with tools/ndi-probe and checks:
#   colours  four-colour clip: frame size, aspect and the colour of each quadrant
#   sync     clip that flashes white and beeps once a second: frame rate, audio,
#            and the offset between flash and beep (A/V sync)
#
# The VLC copy has a "portable" folder, so the test never touches the settings of an
# installed VLC (%APPDATA%\vlc). Needs the NDI 6 Runtime and ffmpeg (for the clips).
# VLC's video window opens for each case: Direct3D 11 hardware decoding (the default on
# Windows) only works with a real video output, not with --vout dummy.
#
# Usage: scripts/test-ndi-windows.sh [case...]      (default: all cases)
# Environment: VLC_VERSION (default 3.0.24), BUILD_DIR (default build/windows-mingw)

set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VLC_VERSION="${VLC_VERSION:-3.0.24}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/windows-mingw}"
PLUGIN_DIR="$BUILD_DIR/out/plugins"
PROBE="$BUILD_DIR/out/tools/ndi-probe.exe"
TEST_DIR="$BUILD_DIR/test"
VLC_SRC="$ROOT/build/vlc-dist/$VLC_VERSION/win64/vlc-$VLC_VERSION"
VLC_DIR="$TEST_DIR/vlc"
mkdir -p "$TEST_DIR"

[[ -x "$PROBE" && -f "$PLUGIN_DIR/libndi_plugin.dll" ]] || {
  echo "Build first: cmake --preset windows-mingw && cmake --build --preset windows-mingw" >&2; exit 1; }
command -v ffmpeg >/dev/null || { echo "ffmpeg is needed to generate the test clips" >&2; exit 1; }
[[ -f "$VLC_SRC/vlc.exe" ]] || "$ROOT/apps/scripts/fetch-vlc-win64.sh" "$VLC_VERSION"
if [[ ! -f "$VLC_DIR/vlc.exe" ]]; then
  cp -R "$VLC_SRC" "$VLC_DIR"
fi
mkdir -p "$VLC_DIR/portable"
# The plugin goes into the copy and the plugin cache is rebuilt: without a cache VLC loads
# every plugin at each start, which can take longer than the probe waits.
if ! cmp -s "$PLUGIN_DIR/libndi_plugin.dll" "$VLC_DIR/plugins/video_filter/libndi_plugin.dll"; then
  cp "$PLUGIN_DIR/libndi_plugin.dll" "$VLC_DIR/plugins/video_filter/"
  "$VLC_DIR/vlc-cache-gen.exe" "$(cygpath -w "$VLC_DIR/plugins")"
fi

SW="--codec=avcodec --avcodec-hw=none"
SYNC_TOL_MS=40   # a bit more than one frame at 30 fps

# name | kind | clip | VLC args | expected WxH | expected aspect
CASES=(
  "colours-hw|colours|quad-709||1280x720|1.7778"
  "colours-sw|colours|quad-709|$SW|1280x720|1.7778"
  "colours-anamorphic|colours|quad-601-anamorphic||720x576|1.7778"
  "colours-anamorphic-sw|colours|quad-601-anamorphic|$SW|720x576|1.7778"
  "colours-full-range|colours|quad-full-range||1280x720|1.7778"
  "sync-hw|sync|sync||1280x720|1.7778"
  "sync-sw|sync|sync|$SW|1280x720|1.7778"
)

clip() {
  local f="$TEST_DIR/ndi-$1.mp4"
  if [[ ! -f "$f" ]]; then
    case "$1" in
      quad-709|quad-601-anamorphic|quad-full-range)
        local size=1280x720 matrix=bt709 cs=bt709 sar=1 range=tv fmt=yuv420p
        [[ $1 == quad-601-anamorphic ]] && { size=720x576; matrix=bt601; cs=smpte170m; sar=64/45; }
        [[ $1 == quad-full-range ]] && { range=pc; fmt=yuvj420p; }
        local q="s=$(( ${size%x*} / 2 ))x$(( ${size#*x} / 2 )):r=30"
        ffmpeg -loglevel error -y \
          -f lavfi -i "color=c=0xFF0000:$q" -f lavfi -i "color=c=0x00FF00:$q" \
          -f lavfi -i "color=c=0x0000FF:$q" -f lavfi -i "color=c=0x808080:$q" \
          -filter_complex "[0][1][2][3]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,scale=out_color_matrix=$matrix:out_range=$range,format=$fmt,setsar=$sar" \
          -t 3 -c:v libx264 -colorspace "$cs" -color_range $range "$f" ;;
      sync)
        # White for 2 frames and a 60 ms 1 kHz beep at the start of every second.
        ffmpeg -loglevel error -y \
          -f lavfi -i "color=black:s=1280x720:r=30,drawbox=x=0:y=0:w=iw:h=ih:color=white:t=fill:enable='lt(mod(t,1),0.066)',format=yuv420p" \
          -f lavfi -i "sine=frequency=1000:sample_rate=48000,volume=volume=0:enable='gte(mod(t,1),0.06)'" \
          -t 8 -c:v libx264 -colorspace bt709 -c:a aac -b:a 192k -ac 2 "$f" ;;
    esac
  fi
  echo "$f"
}

run_case() {
  IFS='|' read -r name kind clipname vlcargs want aspect <<<"$1"
  local f log="$TEST_DIR/vlc-ndi-$name.log" src="vsn-test-$name"
  f="$(clip "$clipname")"

  # shellcheck disable=SC2086
  "$VLC_DIR/vlc.exe" -I dummy --dummy-quiet --aout dummy --no-video-title-show \
    --video-filter=ndi --audio-filter=ndi --ndi-name="$src" --loop \
    -vv --file-logging --logfile="$(cygpath -w "$log")" $vlcargs "$(cygpath -w "$f")" >"$log.out" 2>&1 &
  local vlc_pid=$!

  local w=${want%x*} h=${want#*x} args=(--source "($src)" --timeout 30)
  if [[ $kind == colours ]]; then
    args+=(--pixel "$((w / 4)),$((h / 4))" --pixel "$((w * 3 / 4)),$((h / 4))"
           --pixel "$((w / 4)),$((h * 3 / 4))" --pixel "$((w * 3 / 4)),$((h * 3 / 4))")
  else
    args+=(--seconds 6)
  fi
  local out rc=0
  out="$("$PROBE" "${args[@]}" 2>&1 | tr -d '\r')" || rc=$?
  kill "$vlc_pid" 2>/dev/null || true
  wait "$vlc_pid" 2>/dev/null || true

  local chroma
  chroma="$(sed -n 's/.*NDI video filter on \([^ ]*\) .*/\1/p' "$log" | tail -1)"
  echo "--- $name (filter input: ${chroma:-?})"
  grep -vE "^(runtime|source|sync: flash)" <<<"$out" | sed 's/^/  /' || true
  grep -E "ndi .*(error|cannot)" "$log" | sed 's/^/  /' || true
  [[ $rc -eq 0 ]] || { echo "FAIL ($name): probe failed (log: $log)"; return 1; }
  grep -q "^video: $want .*aspect=$aspect" <<<"$out" || { echo "FAIL ($name): expected $want aspect $aspect"; return 1; }

  if [[ $kind == colours ]]; then
    local expect=("255 0 0" "0 255 0" "0 0 255" "128 128 128") i=0 fail=0
    while read -r r g b; do
      read -r er eg eb <<<"${expect[$i]}"
      for pair in "$r:$er" "$g:$eg" "$b:$eb"; do
        local got=${pair%%:*} exp=${pair##*:}
        (( (got > exp ? got - exp : exp - got) <= 8 )) || { echo "  quadrant $i: got $r $g $b"; fail=1; break; }
      done
      i=$((i + 1))
    done < <(sed -n 's/^pixel .*: r=\([0-9]*\) g=\([0-9]*\) b=\([0-9]*\).*/\1 \2 \3/p' <<<"$out")
    (( i == 4 && !fail )) || { echo "FAIL ($name): colours"; return 1; }
  else
    grep -q "^audio: 48000 Hz 2 ch" <<<"$out" || { echo "FAIL ($name): no audio"; return 1; }
    local fps offset
    fps="$(sed -n 's/^video rate: \([0-9.]*\) fps.*/\1/p' <<<"$out")"
    offset="$(sed -n 's/^sync: mean audio offset \([-+0-9.]*\) ms.*/\1/p' <<<"$out")"
    [[ -n $offset ]] || { echo "FAIL ($name): no sync events"; return 1; }
    awk -v f="$fps" 'BEGIN { exit !(f > 29 && f < 31) }' || { echo "FAIL ($name): frame rate $fps"; return 1; }
    awk -v o="$offset" -v t="$SYNC_TOL_MS" 'BEGIN { exit !(o >= -t && o <= t) }' \
      || { echo "FAIL ($name): A/V offset $offset ms"; return 1; }
  fi
  echo "PASS ($name)"
}

status=0
for c in "${CASES[@]}"; do
  name=${c%%|*}
  if (( $# )) && [[ ! " $* " == *" $name "* ]]; then continue; fi
  run_case "$c" || status=1
done
exit $status
