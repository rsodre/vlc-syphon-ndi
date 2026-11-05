# vlc-syphon-ndi

Out-of-tree VLC plugins that publish video frames over **Syphon** (macOS) and **NDI**
(cross-platform), with **Spout** (Windows) planned. They replace the old VLCSyphon fork.

**Start by reading `docs/HANDOVER.md`** (research, architecture, licensing, distribution,
decisions, phased to-do list), then `docs/PHASE0.md` (feasibility results).

## Key decisions (don't reopen without a reason)

- Pass-through **video filter** modules (`"video filter"` capability), built **out of tree**
  against VLC **3.0.x** headers (current release: 3.0.24). This is not a VLC fork.
- Protocol code is kept separate from the VLC API (`shared/core` vs `shared/vlc3`), so a VLC 4
  adapter stays thin.
- Never bundle or commit the NDI runtime. Load `libndi` at runtime from the user's NDI Runtime install.
- License: LGPL-2.1-or-later. Put an SPDX header and copyright line in every source file.
- Universal macOS binaries (arm64 + x86_64), minimum macOS 11.0 (same as official VLC).
  The NDI 6 runtime needs macOS 13. Keep the README's Requirements table current.
- Windows toolchain: MinGW-w64. Releases: GitHub Releases (two apps + plugin zips).
- The apps are the **official VLC.app repackaged**, with no VLC code changed or compiled.
  The apps/launcher seeds defaults from Info.plist (`VSNDefault{Video,Audio}Filter`,
  `VSNDefaultCoreOptions`, e.g. `embedded-video=0`), set in `apps/<App>/app.conf`, on first launch. Bundle IDs are `com.studioavante.*`, and versions are `<vlc>-<build>` (tag `v3.0.24-1`).
- Not a Node project: C/Objective-C with CMake (presets: `macos`, `linux`, `windows-mingw`).
- Deliverables: `VLCSyphon.app` (Syphon on by default) and `VLCNDI.app` (NDI on by default,
  NDI-blue icon), both with all plugins, signed and notarized with the maintainer's Apple
  Developer account via Apple's CLI tools (`apps/scripts/release-macos.sh`).

## Working rules

- **Organization:** one folder per plugin under `plugins/<name>/`; code used by more than one
  plugin goes in `shared/`; developer tools in `tools/<name>/`. Every project keeps its sources
  in its own `src/` folder.
- **Ask before installing anything** (Homebrew packages, toolchains, SDKs, apps).
- **Ask before design or architecture decisions**, and offer suggestions.
- **README.md is for humans:** keep install / enable / use, project structure, build and
  distribution instructions current whenever something changes. Welcome Windows/Linux PRs.
- Keep `docs/HANDOVER.md` (decisions, plan checkboxes) current. Commit per phase or task.
- macOS is the focus, but don't break the Linux and Windows (MinGW) builds.

## Build and test

```sh
cmake --preset macos && cmake --build --preset macos   # -> build/macos/out/plugins/
scripts/test-load-macos.sh hello                        # loads it in /Applications/VLC.app via VLC_PLUGIN_PATH
scripts/test-syphon-macos.sh                            # Syphon end to end (uses tools/syphon-probe)
scripts/test-live-toggle-macos.sh                       # enabling/disabling in Preferences applies live
NDI_RUNTIME_DIR_V6=~/Dev/apps/blendy-live/libs/NDI/darwin/macOS scripts/test-ndi-macos.sh   # NDI (tools/ndi-probe)
```

The NDI runtime is not installed on the maintainer's Mac; tests use the SDK copy above.
NDI discovery (mDNS) needs network access outside Claude's sandbox.

`VLC_PLUGIN_PATH` must be an absolute path. On macOS, a visible video window needs `-I macosx`;
with `-I dummy` use `--vout dummy`.

macOS App Management blocks writes into `/Applications/VLC.app`. Don't try to work around it.

App tests must not touch the maintainer's app settings (`com.studioavante.vlcsyphon` / `.vlcndi`):
the maintainer runs those apps between turns. Test a copy with a different bundle ID
(e.g. `com.studioavante.vlcsyphon.test`), remove only that copy's settings afterwards, and only
reset the real apps' settings when asked. A `HOME=` override doesn't isolate Cocoa defaults.
Don't take screenshots of the maintainer's screen.

## Third-party files and references

- `third_party/` holds VLC headers, Syphon.framework and NDI headers only (see its README).
  The latest Syphon and NDI SDKs are in `~/Dev/apps/blendy-live/libs` (copy from there when updating).
- Legacy implementation: `/Users/roger/Dev/XCode/VLCSyphon` (branch `Syphon`,
  https://github.com/rsodre/VLCSyphon). Look at `modules/video_output/syphonServer*.{h,m}`.
  Reference only: don't copy code from it into this repo. Only shipped resources (icons) were copied.
