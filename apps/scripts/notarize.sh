#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Notarizes a signed .app, .dmg or .zip with Apple and staples the ticket
# (apps and DMGs; a zip can't be stapled, Gatekeeper checks it online).
#
# Usage: apps/scripts/notarize.sh <path>
# Environment: NOTARY_PROFILE  keychain profile created with
#              xcrun notarytool store-credentials <profile> ...

set -euo pipefail
target="$1"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to a notarytool keychain profile}"

submit="$target"
if [[ "$target" == *.app ]]; then
  submit="$(mktemp -d)/$(basename "$target" .app).zip"
  ditto -c -k --sequesterRsrc --keepParent "$target" "$submit"
fi

echo "Notarizing $(basename "$target")..."
# Capture first: grepping the live pipe (grep -q exits early) fails under pipefail.
out="$(xcrun notarytool submit "$submit" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 60m 2>&1)" || true
echo "$out" | grep -E "^ *(id|status):"
id="$(echo "$out" | sed -n 's/^ *id: //p' | head -1)"
if ! grep -q "status: Accepted" <<<"$out"; then
  echo "$out" >&2
  [[ -n "$id" ]] && xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" >&2
  echo "Notarization failed for $(basename "$target")" >&2
  exit 1
fi
# Accepted can still carry warnings: show them.
xcrun notarytool log "$id" --keychain-profile "$NOTARY_PROFILE" 2>/dev/null \
  | grep -E '"(severity|message|path)"' | head -20 || true

case "$target" in
  *.app|*.dmg) xcrun stapler staple "$target" && xcrun stapler validate "$target" ;;
esac
