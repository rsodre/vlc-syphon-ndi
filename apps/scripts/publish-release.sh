#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Publishes a locally built release (apps/scripts/release-macos.sh) as a DRAFT GitHub
# release: tags HEAD as v<vlc version>-<build>, pushes the tag, uploads the DMGs, plugin
# zip, VLC source and SHA256SUMS. Review the draft on GitHub, then publish it there.
#
# Usage: apps/scripts/publish-release.sh <build-number>      (needs gh, logged in)
# Environment: VLC_VERSION (default 3.0.24)

set -euo pipefail
BUILD_NUMBER="${1:?usage: publish-release.sh <build-number>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VLC_VERSION="${VLC_VERSION:-3.0.24}"
V="$VLC_VERSION-$BUILD_NUMBER"
TAG="v$V"
OUT="$ROOT/dist/$V"

files=("$OUT"/VLCSyphon-"$V".dmg "$OUT"/VLCNDI-"$V".dmg "$OUT"/vlc-syphon-ndi-plugins-macos-"$V".zip
       "$OUT"/vlc-"$VLC_VERSION".tar.xz "$OUT"/SHA256SUMS)
for f in "${files[@]}"; do [[ -f "$f" ]] || { echo "Missing $f: run apps/scripts/release-macos.sh $BUILD_NUMBER" >&2; exit 1; }; done

# Only notarized builds go out.
for dmg in "$OUT"/*.dmg; do
  spctl -a -t open --context context:primary-signature -v "$dmg" 2>&1 | grep -q "Notarized Developer ID" \
    || { echo "$dmg is not notarized (built without SIGN_IDENTITY?)" >&2; exit 1; }
done
[[ -z "$(git -C "$ROOT" status --porcelain)" ]] || { echo "Commit your changes first" >&2; exit 1; }

git -C "$ROOT" tag -a "$TAG" -m "VLCSyphon & VLCNDI $V"
git -C "$ROOT" push origin "$TAG"
gh release create "$TAG" --repo rsodre/vlc-syphon-ndi --draft --verify-tag \
  --title "VLCSyphon & VLCNDI $V" \
  --notes "VLCSyphon and VLCNDI $V: the official VLC $VLC_VERSION by VideoLAN (unmodified; source attached) with the Syphon and NDI plugins. macOS 11 or later, Apple Silicon and Intel. NDI needs the NDI Runtime (macOS 13+). Install and use: see the README." \
  "${files[@]}"
echo "Draft release $TAG created. Review and publish it on GitHub."
