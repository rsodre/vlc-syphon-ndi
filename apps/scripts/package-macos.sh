#!/usr/bin/env bash
# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Builds VLCSyphon.app and VLCNDI.app from the official VLC.app (unmodified code):
#   - renames the bundle (name, id, icon, version) and sets the default filters
#     (Info.plist keys read by the launcher, apps/launcher)
#   - adds all our plugins and Syphon.framework
#   - turns off VideoLAN's crash reporter and update checks (see below)
#   - rebuilds VLC's plugin cache and re-signs everything (hardened runtime)
#
# Usage: apps/scripts/package-macos.sh [build-number]           (default 1)
# Environment:
#   SIGN_IDENTITY   codesign identity, default "-" (ad-hoc, local testing only).
#                   Releases: "Developer ID Application: <name> (<team>)".
#   VLC_VERSION     default 3.0.24
#   BUILD_DIR       plugins build, default build/macos
# Output: dist/<version>-<build>/VLCSyphon.app, VLCNDI.app

set -euo pipefail

BUILD_NUMBER="${1:-1}"
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
VLC_VERSION="${VLC_VERSION:-3.0.24}"
BUILD_DIR="${BUILD_DIR:-$ROOT/build/macos}"
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
SRC_APP="$ROOT/build/vlc-dist/$VLC_VERSION/VLC.app"
OUT="$ROOT/dist/$VLC_VERSION-$BUILD_NUMBER"
ENTITLEMENTS="$ROOT/apps/resources/VLC.entitlements"
PB=/usr/libexec/PlistBuddy

PLUGINS=(libsyphon_plugin.dylib libndi_plugin.dylib)
for p in "${PLUGINS[@]}" ../apps/vsn-launcher; do
  [[ -f "$BUILD_DIR/out/plugins/$p" ]] || {
    echo "Missing $BUILD_DIR/out/plugins/$p. Build first: cmake --preset macos && cmake --build --preset macos" >&2; exit 1; }
done
[[ -d "$SRC_APP" ]] || "$ROOT/apps/scripts/fetch-vlc-app.sh" "$VLC_VERSION"

sign_flags=(--force --sign "$SIGN_IDENTITY" --options runtime)
[[ "$SIGN_IDENTITY" != "-" ]] && sign_flags+=(--timestamp)

sign() { codesign "${sign_flags[@]}" "$@" 2>&1 | grep -v "replacing existing signature" || true; }

is_macho() { file -b "$1" | grep -q "Mach-O"; }

# Signs nested code inside-out. Bundles (frameworks, helper apps) are signed as a whole
# after their contents.
sign_contents() {
  local app="$1"
  # Plain Mach-O files outside nested bundles (plugins, lib/, helpers), but not the
  # main executables, which are signed last.
  while IFS= read -r -d '' f; do
    case "$f" in */Contents/MacOS/VLC|*/Contents/MacOS/"$APP_NAME") continue ;; esac
    is_macho "$f" && sign "$f"
  done < <(find "$app/Contents/MacOS" -type f -print0)
  # Frameworks: their inner executables and helper apps, then the framework.
  for fw in "$app"/Contents/Frameworks/*.framework; do
    while IFS= read -r -d '' f; do
      is_macho "$f" && sign "$f"
    done < <(find "$fw/Versions" -type f -not -path "*.app/*" -print0)
    while IFS= read -r -d '' helper; do
      while IFS= read -r -d '' f; do is_macho "$f" && sign "$f"; done \
        < <(find "$helper/Contents/MacOS" -type f -print0)
      sign "$helper"
    done < <(find "$fw/Versions" -name "*.app" -type d -prune -print0)
    sign "$fw"
  done
  # VLC itself carries VLC's entitlements (they survive the exec from the launcher).
  sign --entitlements "$ENTITLEMENTS" "$app/Contents/MacOS/VLC"
}

package_app() {
  # shellcheck disable=SC1090
  source "$1"
  local app="$OUT/$APP_NAME.app" plist
  echo "=== $APP_NAME"
  rm -rf "$app"
  ditto "$SRC_APP" "$app"
  plist="$app/Contents/Info.plist"

  # Identity
  $PB -c "Set :CFBundleIdentifier $BUNDLE_ID" \
      -c "Set :CFBundleName $APP_NAME" \
      -c "Set :CFBundleExecutable $APP_NAME" \
      -c "Set :CFBundleIconFile $ICON" \
      -c "Set :CFBundleShortVersionString $VLC_VERSION" \
      -c "Set :CFBundleVersion $VLC_VERSION.$BUILD_NUMBER" "$plist"
  $PB -c "Delete :CFBundleDisplayName" "$plist" 2>/dev/null || true
  $PB -c "Add :CFBundleDisplayName string $APP_NAME" "$plist"
  $PB -c "Delete :NSHumanReadableCopyright" "$plist" 2>/dev/null || true
  $PB -c "Add :NSHumanReadableCopyright string $APP_NAME $VLC_VERSION-$BUILD_NUMBER, based on VLC media player by VideoLAN (GPLv2). Syphon and NDI plugins: Roger Sodre and vlc-syphon-ndi contributors (LGPL-2.1+). Not made or endorsed by VideoLAN." "$plist"
  cp "$ROOT/apps/resources/icons/$ICON" "$app/Contents/Resources/$ICON"

  # Default filters, read by the launcher on first launch.
  $PB -c "Add :VSNDefaultVideoFilter string $DEFAULT_VIDEO_FILTER" \
      -c "Add :VSNDefaultAudioFilter string $DEFAULT_AUDIO_FILTER" "$plist"

  # NDI uses the local network (macOS asks the user once).
  $PB -c "Add :NSLocalNetworkUsageDescription string $APP_NAME uses the local network to send video and audio with NDI." \
      -c "Add :NSBonjourServices array" -c "Add :NSBonjourServices:0 string _ndi._tcp" "$plist"

  # VideoLAN's crash reporter: no Breakpad keys, no reports sent to VideoLAN.
  for k in $($PB -c "Print" "$plist" | sed -n 's/^ *\(Breakpad[A-Za-z]*\) = .*/\1/p'); do
    $PB -c "Delete :$k" "$plist"
  done
  # VideoLAN's updater: VLC hard-codes VideoLAN's update feed, so an update would
  # replace this app with plain VLC. No automatic checks, and a throwaway public key
  # (private half discarded) so any downloaded update fails verification.
  $PB -c "Delete :SUEnableAutomaticChecks" "$plist" 2>/dev/null || true
  $PB -c "Add :SUEnableAutomaticChecks bool false" "$plist"
  openssl dsaparam -genkey 2048 2>/dev/null | openssl dsa -pubout -out "$app/Contents/Resources/dsa_pub.pem" 2>/dev/null

  # Launcher and plugins
  cp "$BUILD_DIR/out/apps/vsn-launcher" "$app/Contents/MacOS/$APP_NAME"
  for p in "${PLUGINS[@]}"; do cp "$BUILD_DIR/out/plugins/$p" "$app/Contents/MacOS/plugins/"; done
  ditto "$ROOT/third_party/syphon/darwin/Syphon.framework" "$app/Contents/Frameworks/Syphon.framework"

  # Where to get the source (GPL): VLC's tarball and this repository.
  cat > "$app/Contents/Resources/SOURCE.txt" <<TXT
$APP_NAME $VLC_VERSION-$BUILD_NUMBER is the official VLC media player $VLC_VERSION for macOS
by VideoLAN, unmodified, with the vlc-syphon-ndi plugins and a small launcher added.

VLC source:      https://download.videolan.org/pub/videolan/vlc/$VLC_VERSION/
                 (also attached to the GitHub release of this app)
Plugins source:  https://github.com/rsodre/vlc-syphon-ndi

VLC is distributed under the GNU GPL v2 or later. The plugins are LGPL-2.1-or-later.
VLC and the VLC cone are trademarks of VideoLAN. This app is not made or endorsed by VideoLAN.
TXT

  # Sign nested code, rebuild the plugin cache (it records each plugin's size and
  # date, which signing changes), then sign and seal the bundle.
  rm -f "$app/Contents/MacOS/plugins/plugins.dat"
  sign_contents "$app"
  # Throwaway HOME: VLC saves a default vlcrc under the app's bundle id, which would
  # stop the launcher from writing the first-run defaults on the user's Mac.
  local tmp_home; tmp_home="$(mktemp -d)"
  HOME="$tmp_home" "$app/Contents/MacOS/VLC" --reset-plugins-cache -I dummy vlc://quit >/dev/null 2>&1 || true
  rm -rf "$tmp_home"
  rmdir "$HOME/Library/Caches/$BUNDLE_ID" 2>/dev/null || true  # created via Cocoa, ignores HOME
  [[ -f "$app/Contents/MacOS/plugins/plugins.dat" ]] || { echo "plugin cache was not written" >&2; exit 1; }
  # Data under Contents/MacOS counts as code: sign it as a generic file (signature in
  # extended attributes), as VideoLAN does.
  sign "$app/Contents/MacOS/plugins/plugins.dat"
  sign "$app"

  codesign --verify --deep --strict "$app"
  echo "$app"
}

mkdir -p "$OUT"
package_app "$ROOT/apps/VLCSyphon/app.conf"
package_app "$ROOT/apps/VLCNDI/app.conf"
echo "Done. Signed with: $SIGN_IDENTITY"
