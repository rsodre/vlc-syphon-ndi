# Handover: from VLCSyphon fork to vlc-syphon-ndi

Written 2026-11-05 at the end of a planning session held in the old repo.
Nothing has been built yet; this document is the starting point.

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
2. **Signed and notarized bundled app** with Syphon (and NDI) on by default:
   - Build official VLC 3.0.24 plus a **one-line patch**: in `src/libvlc-module.c`, change
     the `video-filter` default from `NULL` to `"syphon"` or `"syphon:ndi"`. This keeps the
     user's own Preferences in control.
   - **Don't** inject arguments in `bin/darwinvlc.m`. Command-line arguments override user
     preferences, so users couldn't turn the filter off.
   - Build arm64 and x86_64 separately and merge with `lipo`.
   - Sign every dylib with a Developer ID, the hardened runtime and VLC's entitlements
     (`extras/package/macosx/codesign.sh` is a starting point), then notarize with `notarytool`,
     staple, and package as a DMG.
   - Rebuild for each VLC security release. Automate this in GitHub Actions.
   - Suggested defaults: Syphon on, NDI off or toggleable. NDI broadcasts everything to the LAN
     and triggers a macOS firewall prompt.

## Licensing

- **This repo:** **LGPL-2.1-or-later** (`LICENSE` is already in place). It matches libvlccore and
  VLC's own modules, lets VideoLAN take the code later, and works with the proprietary NDI runtime.
- **Each source file:** `SPDX-License-Identifier: LGPL-2.1-or-later` plus a copyright line.
  Keep the Syphon BSD header only on files actually derived from Syphon's code.
- **The bundled app as a whole** is GPLv2 because it includes VLC's GPL parts, such as the
  macOS interface. Publish the corresponding source for every release.
- **Trademark:** don't call the bundled app "VLC" or use the cone logo. Use our own name and
  icon, and describe it as "based on VLC".
- **NDI:** the runtime is proprietary, so don't bundle it. Users install it themselves
  (DistroAV for OBS works the same way). Follow NDI's branding rules ("NDI®" attribution).
  Before shipping, confirm against the current NDI SDK license.
- **Avoid** Apache-2.0 and GPLv3-only. Both conflict with VLC's GPLv2 parts.

## Plan / next steps

- [ ] **Phase 0 – Feasibility test (go/no-go):** CMake project, "hello world" pass-through
      video filter built against the VLC 3.0.24 headers. Test that it loads in the official signed
      VLC.app on Apple Silicon, then on Windows.
- [ ] **Phase 1 – Syphon filter (macOS):** Metal server, CVPX zero-copy path, CPU fallback, options
      (server name, enable).
- [ ] **Phase 2 – NDI video + audio filters:** load the runtime at startup; show a clear message if
      it's missing.
- [ ] **Phase 3 – Packaging:** plugin-only installer and/or bundled signed app (see Distribution),
      plus a GitHub Actions workflow.
- [ ] **Phase 4 – Spout (Windows).**
- [ ] **Phase 5 – VLC 4 adapter** once 4.0 is stable.

### Open questions

- macOS only first, or Windows in parallel?
- Plugin-only distribution, bundled app, or both? This depends on the Phase 0 result.
- Name for the bundled app.
- NDI on or off by default.

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
