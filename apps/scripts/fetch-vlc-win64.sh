#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Downloads the official VLC for Windows (64-bit zip), checks it against VideoLAN's
# published SHA-256 and extracts it. On Windows it also checks VideoLAN's Authenticode
# signature on vlc.exe.
#
# Usage: apps/scripts/fetch-vlc-win64.sh [version]       (default 3.0.24)
# Environment: CURL (default curl; with an old Git for Windows whose curl fails on
#              certificates, use CURL=/c/Windows/System32/curl.exe)
# Output: build/vlc-dist/<version>/win64/vlc-<version>/

set -euo pipefail

VERSION="${1:-3.0.24}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
OUT="$ROOT/build/vlc-dist/$VERSION/win64"
ZIP="$OUT/vlc-$VERSION-win64.zip"
URL="https://download.videolan.org/pub/videolan/vlc/$VERSION/win64/vlc-$VERSION-win64.zip"
CURL="${CURL:-curl}"

sha256() { if command -v sha256sum >/dev/null; then sha256sum "$1"; else shasum -a 256 "$1"; fi | awk '{print $1}'; }

mkdir -p "$OUT"
if [[ -f "$OUT/vlc-$VERSION/vlc.exe" ]]; then
  echo "$OUT/vlc-$VERSION already extracted"
  exit 0
fi
[[ -f "$ZIP" ]] || { echo "Downloading $URL"; "$CURL" -fSL -o "$ZIP" "$URL"; }

expected="$("$CURL" -fsSL "$URL.sha256" | awk '{print $1}')"
actual="$(sha256 "$ZIP")"
[[ "$expected" == "$actual" ]] || { echo "SHA-256 mismatch: expected $expected, got $actual" >&2; exit 1; }
echo "SHA-256 OK ($actual)"

(cd "$OUT" && cmake -E tar xf "$ZIP")
[[ -f "$OUT/vlc-$VERSION/vlc.exe" ]] || { echo "vlc.exe not found after extracting" >&2; exit 1; }

if command -v powershell.exe >/dev/null && command -v cygpath >/dev/null; then
  exe="$(cygpath -w "$OUT/vlc-$VERSION/vlc.exe")"
  signer="$(powershell.exe -NoProfile -Command \
    "\$s = Get-AuthenticodeSignature -LiteralPath '$exe'; \"\$(\$s.Status) \$(\$s.SignerCertificate.Subject)\"" | tr -d '\r')"
  [[ "$signer" == "Valid CN=VideoLAN,"* ]] || { echo "Unexpected signature: $signer" >&2; exit 1; }
  echo "Signature OK ($signer)"
fi
echo "Extracted $OUT/vlc-$VERSION"
