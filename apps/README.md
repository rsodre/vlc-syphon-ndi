# Bundled apps: VLCSyphon.app and VLCNDI.app

(macOS first. For Windows see [VLCNDI for Windows](#vlcndi-for-windows).)

Both apps are the **official, unmodified VLC** for macOS (universal, from VideoLAN) with
all our plugins added. They differ only in name, bundle ID, icon and which filters are on
by default:

| App | Bundle ID | On by default | Icon |
|---|---|---|---|
| `VLCSyphon.app` | `com.studioavante.vlcsyphon` | `video-filter=syphon` | `resources/icons/VLCSyphon.icns` (orange) |
| `VLCNDI.app` | `com.studioavante.vlcndi` | `video-filter=ndi`, `audio-filter=ndi` | `resources/icons/VLCNDI.icns` (NDI blue) |

Both apps also start with **video in its own window** instead of inside the main window and a
**dark interface**. The defaults live in each app's `app.conf`.

Users switch filters the regular VLC way (Preferences ▸ Show All ▸ Video/Audio ▸ Filters).
Versions follow VLC: `3.0.24 (3.0.24.N)`, released as tag `v3.0.24-N`.

## How an app is made (no VLC code is changed or compiled)

`scripts/package-macos.sh` takes the official `VLC.app` (downloaded and verified by
`scripts/fetch-vlc-app.sh`: VideoLAN's SHA-256 and Developer ID signature) and:

1. **Renames it:** Info.plist name, bundle ID, icon, version, copyright ("based on VLC").
   The icon replaces `CFBundleIconFile`, `VLC.icns` and `VLC-Xmas.icns`, and `CFBundleIconName`
   (VLC's asset-catalog cone, which would win) is removed.
   VLC 3 names its preferences, data and cache folders after the bundle ID, so each app
   has its own settings, separate from the official VLC.
2. **Sets the default filters** with a tiny launcher (`launcher/src/main.c`) that becomes the
   bundle's executable. On first launch only, it writes the app's `vlcrc` with the filters
   named in the Info.plist keys `VSNDefaultVideoFilter` / `VSNDefaultAudioFilter` and the
   `option=value` lines in `VSNDefaultCoreOptions` (both apps: `control=syphon:ndi`, which starts the Syphon server / NDI source with the app when their
   filter is enabled; `embedded-video=0`, video in its own window; and `macosx-interfacestyle=1`,
   dark interface). It also marks VLC's
   first-run question ("Check for album art and metadata?") as answered, with online metadata
   left off (VLC's default): that modal question made VLC lose the separate video window when a
   file was opened at first launch. Then it
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

## VLCNDI for Windows

The same idea, from VideoLAN's `vlc-<version>-win64.zip` (downloaded and verified by
`scripts/fetch-vlc-win64.sh`: VideoLAN's SHA-256, and on Windows the Authenticode signature of
`vlc.exe`). `scripts/package-windows.sh` copies it to `dist/<version>-<build>/VLCNDI/` and adds:

- `plugins\video_filter\libndi_plugin.dll`, the NDI plugin (there is no Syphon on Windows, so
  there is no VLCSyphon either).
- `VLCNDI.exe`, the launcher (`launcher/src/main_windows.c`), with the NDI-blue icon
  (`resources/icons/VLCNDI.ico`) and the version `3.0.24.N`.
- `VLCNDI-defaults.vlcrc`, the first-launch settings from `VLCNDI/app.conf`: the default filters
  and `WINDOWS_CORE_OPTIONS` (`control=ndi`, `embedded-video=0`, `qt-privacy-ask=0` so VLC's
  privacy question isn't shown and online metadata stays off, `qt-updates-notif=0` so VLC doesn't
  offer to install plain VLC over it).
- `SOURCE.txt`.

It is a **portable zip**, not an installer. What the launcher does on each start:

1. Creates the folder `portable` next to `vlc.exe`. VLC for Windows keeps its settings and caches
   there when it exists (its own portable mode) instead of `%APPDATA%\vlc`, which every VLC on the
   PC shares. That gives VLCNDI its own settings without any command-line option. The folder must
   be writable, so the app can't live in Program Files (the launcher says so).
2. If there is no `portable\vlcrc` yet, copies `VLCNDI-defaults.vlcrc` to it.
3. If `plugins\plugins.dat` is missing, runs VLC's `vlc-cache-gen.exe` to write it, as VLC's
   installer does. VideoLAN's zip has no plugin cache, and without one VLC loads every plugin at
   each start.
4. Starts `vlc.exe` with the same arguments, waits for it and returns its exit code.

Differences from the macOS apps:

- **Not signed.** There is no Windows code-signing certificate, so SmartScreen warns on first run.
  VLC's own files keep VideoLAN's signatures.
- **Crash reports** can't be turned off without changing VLC: after a crash, VLC asks whether to
  send a report to VideoLAN (nothing is sent without a Yes). The dumps are in
  `%APPDATA%\vlc\crashdump`, shared with an installed VLC.
- The taskbar shows VLC's cone while the app runs (the window belongs to `vlc.exe`).
- No dark interface in VLC 3 for Windows.

`scripts/release-windows.sh <build>` builds, packages and zips. `scripts/publish-windows.sh <build>`
uploads the zips to the existing GitHub release and merges their checksums into its `SHA256SUMS`.
Both run in Git Bash on Windows (CMake, Ninja, an msvcrt MinGW-w64 toolchain and `gh` in `PATH`)
or on Linux/macOS after a cross build.

## Scripts

| Script | |
|---|---|
| `scripts/fetch-vlc-win64.sh [version]` | Windows: download and verify the official 64-bit VLC zip |
| `scripts/package-windows.sh [build]` | Windows: make `dist/<version>-<build>/VLCNDI/` |
| `scripts/release-windows.sh <build>` | Windows: build, package, zip the app and the plugin, `SHA256SUMS.windows` |
| `scripts/publish-windows.sh <build>` | Windows: add the zips to the GitHub release |
| `scripts/make-ico.ps1` | regenerate `VLCNDI.ico` from `VLCNDI.icns` (PowerShell) |
| `scripts/fetch-vlc-app.sh [version]` | download and verify the official universal VLC |
| `scripts/package-macos.sh [build]` | make both apps in `dist/<version>-<build>/` |
| `scripts/make-dmg.sh <app> <dmg>` | DMG with an Applications shortcut |
| `scripts/notarize.sh <app/dmg/zip>` | notarize and staple |
| `scripts/package-plugins-macos.sh <zip>` | plugin zip for the official VLC |
| `scripts/release-macos.sh <build>` | all of the above, plus VLC's source and `SHA256SUMS` |
| `scripts/publish-release.sh <build>` | tag and create a draft GitHub release from `dist/` |
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

4. Publish: `apps/scripts/publish-release.sh 1` checks the DMGs are notarized, tags `v3.0.24-1`,
   pushes the tag and creates a **draft** GitHub release with both DMGs, the plugin zip, VLC's
   source and `SHA256SUMS`. Review it on GitHub and publish it there.

Releases are built locally for now (no release CI). `.github/workflows/build.yml` only checks
that the plugins compile on macOS, Linux and Windows.

## Licensing notes

VLC is GPLv2+: each release ships VLC's source tarball, and the plugins' source is this
repository. The apps keep the "VLC" name and a cone-derived icon by the maintainer's choice
(see docs/HANDOVER.md, Branding) and say they are not made or endorsed by VideoLAN.
