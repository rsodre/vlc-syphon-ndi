#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Adds a locally built Windows release (apps/scripts/release-windows.sh) to the GitHub
# release v<vlc version>-<build>, which publish-release.sh created from the macOS build:
# uploads the two Windows zips and merges their checksums into the release's SHA256SUMS.
# Running it again replaces the Windows files. The release description is not changed:
# edit it on GitHub.
#
# Usage: apps/scripts/publish-windows.sh <build-number>      (needs gh, logged in)
# Environment: VLC_VERSION (default 3.0.24)

set -euo pipefail
BUILD_NUMBER="${1:?usage: publish-windows.sh <build-number>}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VLC_VERSION="${VLC_VERSION:-3.0.24}"
V="$VLC_VERSION-$BUILD_NUMBER"
TAG="v$V"
OUT="$ROOT/dist/$V"
REPO="rsodre/vlc-syphon-ndi"

files=("$OUT/VLCNDI-$V-win64.zip" "$OUT/vlc-syphon-ndi-plugins-windows-$V.zip")
for f in "${files[@]}" "$OUT/SHA256SUMS.windows"; do
  [[ -f "$f" ]] || { echo "Missing $f: run apps/scripts/release-windows.sh $BUILD_NUMBER" >&2; exit 1; }
done
(cd "$OUT" && { if command -v sha256sum >/dev/null; then sha256sum -c SHA256SUMS.windows; else shasum -a 256 -c SHA256SUMS.windows; fi; })

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
gh release download "$TAG" --repo "$REPO" --pattern SHA256SUMS --dir "$tmp"
# The release's checksums without any earlier Windows lines, then the new ones.
{ grep -v -e "-win64\.zip\$" -e "-plugins-windows-" "$tmp/SHA256SUMS" | tr -d '\r' || true
  tr -d '\r' < "$OUT/SHA256SUMS.windows"; } > "$tmp/merged"
mv "$tmp/merged" "$tmp/SHA256SUMS"
cat "$tmp/SHA256SUMS"

gh release upload "$TAG" --repo "$REPO" --clobber "${files[@]}" "$tmp/SHA256SUMS"
echo "Windows files added to release $TAG. Update the release description on GitHub if needed."
