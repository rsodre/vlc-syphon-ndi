# Handover: from VLCSyphon fork to vlc-syphon-ndi

Written 2026-11-05 at the end of a planning session held in the old repo, then updated
the same day with the maintainer's decisions and the Phase 0 result
(see [Decisions (2026-11-05)](#decisions-2026-11-05) and [PHASE0.md](PHASE0.md)).

## Background

The old project, **VLCSyphon** (`/Users/roger/Dev/XCode/VLCSyphon`, branch `Syphon`,
GitHub repo archived Oct 2025), is a fork of VLC 3.0.0-git from mid-2016.
It patches VLC's own source files instead of being a separate plugin:

- `modules/video_output/macosx.m`: calls `syphon_open()`, `syphon_close()` and
  `syphon_display_opengl_Display()` from the macOS OpenGL video output.
- `modules/video_output/opengl.c`: wrapped in `#ifndef SYPHON_SERVER` so that
  `syphonServer_texture.m` can `#include` it and reuse its texture upload/shader code.
  It also forces alpha to 1 in the YUV fragment shader.
- `modules/video_output/Makefile.am`: links `Syphon.framework` into `libvout_macosx_plugin`.
- `build/make_syphon`: builds the app and packs it as `VLCSyphon.app`.

To see the whole Syphon change set in the old repo, run
`git diff f2de0fc0fa..HEAD -- modules/video_output` there.
`f2de0fc0fa` is the last upstream VLC commit.

What's wrong with that design: Syphon works only with that one OpenGL video
output, which VLC has since reworked, and every VLC upgrade means a manual rebase.
**Use the old repo only as reference for the Syphon publishing logic. Don't copy it wholesale.**

## Decisions (2026-11-05)

These answer the earlier open questions and set the working rules.

- **Platforms:** macOS (Syphon, NDI) first. Windows (including Spout) and Linux must stay
  buildable so a contributor can pick them up: CMake presets and CI exist for all three.
- **Deliverables:** two signed, notarized macOS apps built with the maintainer's Apple Developer
  account and Apple's command-line tools:
  - **VLCSyphon.app**: Syphon on by default. Orange inverted-cone icon from the legacy repo.
  - **VLCNDI.app**: NDI on by default. Same icon, tinted NDI blue.
  - Both contain **all** plugins. Users switch them the regular VLC way (Preferences ▸ Video ▸
    Filters, or `--video-filter`).
  - Published as **GitHub Releases**: both apps (DMGs) plus plugin zips per platform. Plugin users
    follow the usual VLC plugin instructions in the README (on macOS, `VLC_PLUGIN_PATH` is recommended).
  - **Superseded in Phase 3:** the apps are the official VLC.app repackaged, not built from
    source. A small launcher reads the default filters from the app's **Info.plist** and seeds
    them on first launch (see apps/README.md). The bundle IDs are `com.studioavante.vlcsyphon`
    and `com.studioavante.vlcndi`. VLC 3 names its settings folders after the bundle ID, so each app
    has its own settings without any patch. Versions are `3.0.24 (3.0.24.N)`, and tags are `v3.0.24-N`.
- **Windows toolchain: MinGW-w64** (llvm-mingw or MSYS2), the same as VLC's own Windows builds.
  VLC's headers assume GCC/Clang. Spout2's DirectX 11 sender code builds with MinGW too.
- **NDI runtime:** users need **only** the NDI Runtime (macOS: `libNDI_for_Mac.pkg` from
  http://ndi.link/NDIRedistV6Apple, installs `/usr/local/lib/libndi.dylib`). NDI Tools is not
  needed: on macOS its apps embed private copies and install no shared runtime. Error messages
  and docs say so. Loading the copy inside
  an NDI Tools app was considered and not done: it's another app's private file.
- **Always-on outputs (maintainer's spec):** while a plugin is enabled, its Syphon server / NDI
  source stays up as long as VLC is open. No video means fully transparent: 1920×1080 at launch,
  the last size after a video closes. Playing: the video at its size. End with Play and pause: last frame.
  Filters only exist while a video does, so the launch part is a **control interface** submodule
  in each plugin (`--control=syphon:ndi`, seeded by the apps). It's inert unless its filter is enabled.
  NDI repeats the last frame once a second when idle, because receivers only get frames sent after they connect.
  The control interfaces also apply Preferences changes **live** (polling the saved setting twice a
  second and changing the running vout/aout filter lists), so no restart is needed.
- **NDI colours:** the NDI 6.3.2 SDK receiver decodes every resolution as BT.709 limited range,
  although NDI's docs say BT.601 for SD. The sender normalises to BT.709 by default
  (`--ndi-bt709`, can be turned off).
- **VideoLAN addons site:** addons.videolan.org exists, but as far as we know it hosts Lua
  extensions, skins and playlist parsers. VLC's built-in addon manager doesn't install native
  plugins. Optionally list the project there with a link to GitHub Releases (Phase 3), and later
  offer the plugins to VideoLAN upstream (they are LGPL for that reason).
- **Branding:** the maintainer keeps the "VLC…" names and the cone-derived icon, knowingly
  accepting the trademark risk described under Licensing. Revisit if VideoLAN objects.
- **Not a Node project.** No package.json or pnpm workspace. C/Objective-C with CMake.
- **Repository layout:** each plugin in its own folder under `plugins/`; code used by more than
  one plugin goes in `shared/`. Every project keeps its source code in its own `src/` folder.
  See the README for the full tree.
- **Third-party files** are committed under `third_party/` (the repo is public):
  VLC 3.0.24 headers (LGPL), `Syphon.framework` (BSD), NDI SDK **headers only** (MIT).
  The NDI runtime and the rest of the NDI SDK are never committed. Local copies of the
  latest Syphon and NDI SDKs live in `~/Dev/apps/blendy-live/libs`.
- **Legacy code:** don't keep code from VLCSyphon here. Reference it by name and URL:
  [rsodre/VLCSyphon](https://github.com/rsodre/VLCSyphon) (branch `Syphon`). Only resources we
  ship (icons) were copied.
- **Process:** ask the maintainer before installing anything, and before any design or
  architecture decision (with suggestions). The README is for humans: keep it current.

## Research findings (Nov 2026)

- **VLC versions:** the latest stable release is **3.0.24** (2026-09-22). It moved to FFmpeg 8.1.2
  and fixed 130+ security issues. VLC 4.0 is still nightly/beta only.
- **Syphon:** no VLC release includes it. VLCSyphon appears to be the only implementation.
- **Spout:** no VLC module exists. A 2016 VideoLAN forum request was never answered with one.
- **NDI:** NDI Tools ships a proprietary VLC plugin for Windows and Mac with NDI video and
  audio outputs. It **replaces** local playback, so VLC stops showing the video on screen.
  A pass-through filter would let local playback continue while streaming, which is a reason to build our own.
- **Lua extensions can't access video frames.** It must be a native module.

## Architecture decision

Build **pass-through video filter modules** (capability `"video filter"`), out of tree,
against the VLC 3.0.x headers. A module built against the 3.0 headers loads in every 3.0.x release.

Why a filter:
- It works with any video output, on any OS.
- It publishes frames at full source resolution, not limited to the window size.
- Local playback continues unchanged.
- Users enable it with `--video-filter=syphon:ndi` or in Preferences ▸ Video ▸ Filters.

Known limitation: subtitles and the on-screen display are drawn after the filter,
so they don't appear in the shared frames.

Rejected options:
- Custom video output plus the `clone` splitter: forces frames into CPU memory and is clumsy to configure.
- Stream output (`sout`) module: receives encoded streams, so it would need to decode/transcode.
- Lua extension: can't access frames.
- Fork VLC: the upgrade problem we're leaving behind.

### Plugins

| Module | Platform | Notes |
|---|---|---|
| `syphon` | macOS | Use the Syphon **Metal** server. Keep VideoToolbox (CVPX) hardware-decoded frames on the GPU (CVPixelBuffer → IOSurface → convert to RGBA on the GPU). CPU-upload fallback for software-decoded frames. |
| `ndi` (+ `ndi` audio filter) | macOS, Windows, Linux | CPU path. NDI accepts NV12/I420/UYVY directly. Load `libndi` **at runtime** from the user-installed NDI Runtime. **Never bundle it.** |
| `spout` | Windows | Later phase. Spout2 DirectX 11 sender. Zero copy for Direct3D 11 hardware-decoded frames. |

Keep the protocol code separate from VLC's API, so a VLC 4 adapter is thin later.

## Distribution

Two ways to ship:

1. **Plugin only**, dropped into the official `VLC.app/Contents/MacOS/plugins`
   (or `plugins\video_filter\` on Windows, followed by `vlc --reset-plugins-cache`).
   **Untested risk:** adding a file breaks the signed bundle's seal, and newer macOS
   versions may block changes to other developers' apps. VLC disables library validation
   (hardened-runtime entitlements added in 2018), so a plugin signed with our Developer ID
   *should* load. Fallback: a launcher that sets `VLC_PLUGIN_PATH`.
   **Phase 0 result:** on macOS 26, App Management protection blocks writing into
   `/Applications/VLC.app` (`Operation not permitted`), and the plugin would break the seal anyway.
   `VLC_PLUGIN_PATH` works with the untouched official app. See [PHASE0.md](PHASE0.md).
2. **Signed and notarized bundled apps** (VLCSyphon.app and VLCNDI.app, see Decisions).
   *Phase 3 replaced the build-from-source plan below with repackaging the official app
   (apps/README.md). VideoLAN has no prebuilt 3.0 contribs for Apple Silicon, so a source
   build means ~70 libraries compiled per architecture with Xcode 27. The plan is kept for reference:*
   - Build official VLC 3.0.24 plus a **one-line patch**: in `src/libvlc-module.c`, change
     the `video-filter` default from `NULL` to `"syphon"` (VLCSyphon) or `"ndi"` (VLCNDI).
     This keeps the user's own Preferences in control. **Decided:** one VLC build for both apps,
     with a small patch that reads the default from a key in the bundle's Info.plist.
   - **Don't** inject arguments in `bin/darwinvlc.m`. Command-line arguments override user
     preferences, so users couldn't turn the filter off.
   - Build arm64 and x86_64 separately and merge with `lipo`.
   - Sign every dylib with a Developer ID, the hardened runtime and VLC's entitlements
     (`extras/package/macosx/codesign.sh` is a starting point), then notarize with `notarytool`,
     staple, and package as a DMG.
   - Rebuild for each VLC security release (locally for now: release-macos.sh + publish-release.sh).
   - NDI broadcasts to the LAN and triggers a macOS firewall prompt, which is expected in VLCNDI.app.
   - Each app needs its own bundle ID and its own VLC preferences folder, so the two apps and
     an official VLC on the same Mac don't share settings. Check this in Phase 3.

## Licensing

- **This repo:** **LGPL-2.1-or-later** (`LICENSE` is already in place). It matches libvlccore and
  VLC's own modules, lets VideoLAN take the code later, and works with the proprietary NDI runtime.
- **Each source file:** `SPDX-License-Identifier: LGPL-2.1-or-later` plus a copyright line.
  Keep the Syphon BSD header only on files actually derived from Syphon's code.
- **The bundled app as a whole** is GPLv2 because it includes VLC's GPL parts, such as the
  macOS interface. Publish the corresponding source for every release.
- **Trademark:** VideoLAN's policy discourages calling a modified build "VLC" or using the cone
  logo. The maintainer chose to keep "VLCSyphon"/"VLCNDI" and the cone-derived icon anyway
  (see Decisions). Describe the apps as "based on VLC" and don't imply VideoLAN endorsement.
- **NDI:** the runtime is proprietary, so don't bundle it. Users install it themselves
  (DistroAV for OBS works the same way). Follow NDI's branding rules ("NDI®" attribution).
  Before shipping, confirm against the current NDI SDK license.
- **Avoid** Apache-2.0 and GPLv3-only. Both conflict with VLC's GPLv2 parts.

## Plan / next steps

- [x] **Phase 0 – Feasibility test (go/no-go): GO on macOS.** CMake project, `hello` pass-through
      filter built against vendored VLC 3.0.24 headers, loads in the official VLC.app via
      `VLC_PLUGIN_PATH` and gets GPU (CVPX) frames. Details: [PHASE0.md](PHASE0.md).
      - [ ] Windows load test (needs a Windows machine or contributor).
      - [ ] Linux load test.
      - [ ] Confirm the CI workflow passes on all three platforms after the first push.
- [x] **Phase 1 – Syphon filter (macOS):** Metal server, CVPX zero-copy path, CPU fallback,
      options `syphon-name` and `syphon-square-pixels` (enabling is VLC's own filter list).
      End-to-end tests in `scripts/test-syphon-macos.sh` (8 cases), also checked in the VLC GUI.
      Details: [plugins/syphon/README.md](../plugins/syphon/README.md).
      - [ ] Later: HDR (PQ/HLG) tone mapping.
- [x] **Phase 2 – NDI video + audio filters (macOS):** runtime loaded on first frame from
      `NDI_RUNTIME_DIR_V6` or the default install path; a one-time error dialog if missing.
      Frames are sent at their presentation time by a worker thread (A/V offset ~+14 ms).
      SD/full-range colours normalised to BT.709 (`--ndi-bt709`). Tests: `scripts/test-ndi-macos.sh`
      (7 cases). Details: [plugins/ndi/README.md](../plugins/ndi/README.md).
      - [ ] Run on Windows and Linux (contributors).
      - [ ] Test with a real audio output and with third-party receivers (OBS/DistroAV, vMix, NDI Studio Monitor).
- [x] **Phase 3 – Packaging (macOS):** official VLC 3.0.24 universal repackaged into
      VLCSyphon.app / VLCNDI.app (launcher seeds default filters; per-app settings; Breakpad
      and Sparkle disconnected; plugin cache rebuilt; re-signed). Both apps tested by launching
      them with a file: Syphon frames correct, NDI picture + sound with +6 ms A/V offset through the
      real audio output. DMGs, plugin zip, VLC source and checksums from
      `apps/scripts/release-macos.sh`, published as a draft by `apps/scripts/publish-release.sh`.
      Releases are built locally (maintainer's choice; the release CI was removed).
      - [ ] Developer ID certificate + notarytool profile (maintainer), then the first signed
            release and notarization run.
      - [ ] Manual checklist: docs/TESTING-APPS.md.
      (Original notes: VLCNDI.app must default both `video-filter` and
      `audio-filter` to `ndi`; keep VLC's `disable-library-validation` entitlement, which is what lets
      the NDI runtime from `/usr/local/lib` load; add `NSLocalNetworkUsageDescription` to Info.plist.)
- [ ] **Phase 4 – Spout (Windows).**
- [ ] **Phase 5 – VLC 4 adapter** once 4.0 is stable.

### Open questions

- Phase 3: list the project on addons.videolan.org?

## Sources

- VLC releases: https://www.videolan.org/vlc/releases/
- 3.0.24 release notes: https://github.com/videolan/vlc/releases/tag/3.0.24
- VideoLAN legal / trademark policy: https://www.videolan.org/legal.html
- NDI for VLC: https://docs.ndi.video/all/using-ndi/ndi-tools/plugins/ndi-for-vlc
- VLC Spout request: https://forum.videolan.org/viewtopic.php?t=130785
- Hardened-runtime entitlements commit: https://mailman.videolan.org/pipermail/vlc-commits/2018-October/052563.html
- DistroAV (GPL OBS NDI plugin, runtime installed by the user): https://github.com/DistroAV/DistroAV
- NDI license discussion: https://obsproject.com/forum/threads/ndi.47104/page-2
- Spout2: https://github.com/leadedge/Spout2
