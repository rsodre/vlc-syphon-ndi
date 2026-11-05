# Bundled apps: VLCSyphon.app and VLCNDI.app

Both apps are the **official, unmodified VLC** for macOS (universal, from VideoLAN) with
all our plugins added. They differ only in name, bundle ID, icon and which filters are on
by default:

| App | Bundle ID | On by default | Icon |
|---|---|---|---|
| `VLCSyphon.app` | `com.studioavante.vlcsyphon` | `video-filter=syphon` | `resources/icons/VLCSyphon.icns` (orange) |
| `VLCNDI.app` | `com.studioavante.vlcndi` | `video-filter=ndi`, `audio-filter=ndi` | `resources/icons/VLCNDI.icns` (NDI blue) |

Users switch filters the regular VLC way (Preferences ▸ Show All ▸ Video/Audio ▸ Filters).
Versions follow VLC: `3.0.24 (3.0.24.N)`, released as tag `v3.0.24-N`.

## How an app is made (no VLC code is changed or compiled)

`scripts/package-macos.sh` takes the official `VLC.app` (downloaded and verified by
`scripts/fetch-vlc-app.sh`: VideoLAN's SHA-256 and Developer ID signature) and:

1. **Renames it:** Info.plist name, bundle ID, icon, version, copyright ("based on VLC").
   VLC 3 names its preferences, data and cache folders after the bundle ID, so each app
   has its own settings, separate from the official VLC.
2. **Sets the default filters** with a tiny launcher (`launcher/src/main.c`) that becomes the
   bundle's executable. On first launch only, it writes the app's `vlcrc` with the filters
   named in the Info.plist keys `VSNDefaultVideoFilter` / `VSNDefaultAudioFilter`, then
   `exec`s VLC's own executable. After that they are ordinary preferences. No command-line
   options are injected, so the user's choices always win.
   Note: VLC's "Reset Preferences" writes VLC's own defaults, so the filter is off afterwards.
   Users turn it back on in Preferences, or delete the app's preferences folder to get the
   app's defaults again.
3. **Adds the plugins** (`Contents/MacOS/plugins/`) and `Syphon.framework` (`Contents/Frameworks/`).
4. **Disconnects VideoLAN services:**
   - Crash reports: Breakpad's Info.plist keys are removed, so nothing goes to VideoLAN.
   - Updates: VLC hard-codes VideoLAN's update feed, so an update would turn the app back
     into plain VLC. Automatic checks are off, and the update public key is replaced with a
     throwaway one (private half discarded), so a downloaded update fails verification.
5. **Adds NDI's local-network entries** (`NSLocalNetworkUsageDescription`, `NSBonjourServices`).
6. **Rebuilds VLC's plugin cache and re-signs** everything inside-out with the hardened
   runtime and VLC's own entitlements (`resources/VLC.entitlements`, which include
   `disable-library-validation`, needed to load the NDI runtime).
7. Adds `Contents/Resources/SOURCE.txt` saying where VLC's source is (GPL).

Release packaging (`scripts/release-macos.sh`) then notarizes and staples each app, packs and
notarizes the DMGs, zips the plugins for the official VLC, and copies VLC's source tarball
next to them.

## Scripts

| Script | |
|---|---|
| `scripts/fetch-vlc-app.sh [version]` | download and verify the official universal VLC |
| `scripts/package-macos.sh [build]` | make both apps in `dist/<version>-<build>/` |
| `scripts/make-dmg.sh <app> <dmg>` | DMG with an Applications shortcut |
| `scripts/notarize.sh <app/dmg/zip>` | notarize and staple |
| `scripts/package-plugins-macos.sh <zip>` | plugin zip for the official VLC |
| `scripts/release-macos.sh <build>` | all of the above, plus VLC's source and `SHA256SUMS` |
| `scripts/make-icons.sh` | regenerate the NDI-blue icon from the orange one |

Without `SIGN_IDENTITY` everything is signed ad hoc, which is fine for local testing
but not for distribution (Gatekeeper rejects it on other Macs).

## Signing setup (once)

1. A **Developer ID Application** certificate (needs the Account Holder role): Xcode ▸
   Settings ▸ Accounts ▸ Manage Certificates ▸ + ▸ Developer ID Application. Check with
   `security find-identity -v -p codesigning`.
2. Notarization credentials in the keychain, e.g. with an app-specific password
   (appleid.apple.com ▸ Sign-In and Security ▸ App-Specific Passwords):

   ```sh
   xcrun notarytool store-credentials vsn-notary \
     --apple-id <your Apple ID> --team-id <TEAMID> --password <app-specific password>
   ```
3. Release locally:

   ```sh
   SIGN_IDENTITY="Developer ID Application: <Name> (<TEAMID>)" NOTARY_PROFILE=vsn-notary \
     apps/scripts/release-macos.sh 1
   ```

For GitHub Actions (`.github/workflows/release.yml`, runs on tags `v*`), add the secrets
listed at the top of that file. It drafts a release with both DMGs, the plugin zips
(macOS; Linux and Windows experimental), VLC's source and `SHA256SUMS`.

## Licensing notes

VLC is GPLv2+: each release ships VLC's source tarball, and the plugins' source is this
repository. The apps keep the "VLC" name and a cone-derived icon by the maintainer's choice
(see docs/HANDOVER.md, Branding) and say they are not made or endorsed by VideoLAN.
