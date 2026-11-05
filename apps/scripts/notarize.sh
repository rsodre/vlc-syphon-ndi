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
xcrun notarytool submit "$submit" --keychain-profile "$NOTARY_PROFILE" --wait --timeout 60m \
  | tee /dev/stderr | grep -q "status: Accepted" || {
    echo "Notarization failed. Inspect with: xcrun notarytool log <id> --keychain-profile $NOTARY_PROFILE" >&2
    exit 1; }

case "$target" in
  *.app|*.dmg) xcrun stapler staple "$target" && xcrun stapler validate "$target" ;;
esac
