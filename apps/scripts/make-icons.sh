#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Regenerates apps/resources/icons/VLCNDI.icns (NDI-blue) from VLCSyphon.icns (orange).
# Usage: apps/scripts/make-icons.sh [hue-degrees]   (default 180)

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ICONS="$HERE/../resources/icons"
HUE="${1:-180}"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

iconutil -c iconset -o "$WORK/in.iconset" "$ICONS/VLCSyphon.icns"
swift "$HERE/tint-icon.swift" "$WORK/in.iconset" "$WORK/VLCNDI.iconset" "$HUE"
iconutil -c icns -o "$ICONS/VLCNDI.icns" "$WORK/VLCNDI.iconset"
cp "$WORK/VLCNDI.iconset/icon_512x512.png" "$ICONS/VLCNDI.png"
sips -Z 200 "$ICONS/VLCNDI.png" >/dev/null
echo "Wrote $ICONS/VLCNDI.icns and VLCNDI.png"
