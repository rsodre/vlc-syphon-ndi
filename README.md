<p>
  <img src="apps/resources/icons/VLCSyphon.png" width="100" alt="VLCSyphon icon">
  <img src="apps/resources/icons/VLCNDI.png" width="100" alt="VLCNDI icon">
</p>

# vlc-syphon-ndi

VLC plugins that share the video you're playing with other apps, live, at full resolution:

- **Syphon** (macOS): use VLC as a video source in Resolume, MadMapper, TouchDesigner, OBS, etc.
- **NDI®** (macOS, Windows, Linux): send VLC's video over the network to any NDI receiver.
- **Spout** (Windows): planned. [Contributions welcome](#contributing).

They are **video filters**, so VLC keeps playing normally on screen while it shares each frame.
Frames are published at the file's own resolution, not the window size.

This project replaces [VLCSyphon](https://github.com/rsodre/VLCSyphon), which was a fork of VLC.

> **Status:** early development. The **Syphon** and **NDI** plugins work with VLC 3.0.24 on macOS,
> and the apps can be built locally. The first signed release is coming soon.

## Requirements

| | macOS | Windows | Linux |
|---|---|---|---|
| **VLCSyphon.app / VLCNDI.app** | macOS 11 Big Sur or later, Apple Silicon or Intel (universal app) | — | — |
| **Syphon plugin** | macOS 11 or later, Apple Silicon or Intel, with VLC 3.0.x | — | — |
| **NDI plugin** | macOS 13 Ventura or later (required by the current NDI 6 runtime) | planned, Windows 10+ 64-bit | planned, x86_64 |
| **Spout plugin** | — | planned | — |

- **VLC:** 3.0.x, 64-bit. Built and tested against 3.0.24, the current release. VLC 4 isn't supported yet.
- **Graphics:** the Syphon plugin uses Metal, which every Mac that runs macOS 11 has. Hardware-decoded
  video stays on the GPU; other video is uploaded from the CPU, which costs more for 4K.
- **Syphon clients:** any Syphon-enabled app (Resolume, MadMapper, TouchDesigner, OBS with a Syphon
  plugin, …). Metal and OpenGL clients both work.
- **NDI:** only the free **NDI Runtime** is required ([macOS](http://ndi.link/NDIRedistV6Apple), [Windows](http://ndi.link/NDIRedistV6);
  Linux: `libndi.so.6` from the [NDI SDK](https://ndi.video/for-developers/ndi-sdk/)). NDI Tools is
  not needed (its apps are handy for viewing the output, but they don't install the runtime).
  A wired network is recommended for HD and above.

## Download

Everything will be on the [GitHub Releases](https://github.com/rsodre/vlc-syphon-ndi/releases) page
(coming soon):

| App | What it is |
|---|---|
| **VLCSyphon.app** | VLC 3.0.24 with all plugins installed, **Syphon on** by default |
| **VLCNDI.app** | VLC 3.0.24 with all plugins installed, **NDI on** by default |
| **Plugin zips** | Just the plugins, per platform, to add to the official VLC ([install](#install-the-plugins-into-an-existing-vlc)) |

Both apps are the official VLC with every plugin added, so you can turn Syphon and NDI on or
off in either one. Each app keeps its own settings, separate from the official VLC. They are
based on VLC but are not made or endorsed by VideoLAN, and they don't update themselves: get
new versions from Releases.

Install: open the DMG and drag the app to Applications. Unlike the official VLC, the apps don't
ask about album art and metadata on first launch. Online metadata lookup stays off (VLC's
default); turn it on in Preferences ▸ Interface ▸ "Allow metadata network access".

While a plugin is enabled, its Syphon server or NDI source **stays up the whole time VLC is
open**, even with nothing playing:

| When | Syphon server / NDI source shows |
|---|---|
| VLC starts (filter enabled) | fully transparent, 1920×1080 |
| A file plays | its video, at its resolution |
| The file ends with Play and pause on | the last frame |
| The file ends otherwise, the video window closes, or Stop | fully transparent at the last size |
| VLC quits | the server / source goes away |

Both apps start with these VLC settings, which you can change in Preferences:

- **Video in its own window**, not inside the main window (Video ▸ "Show video within the main
  window" off).
- **Dark interface** (Interface ▸ "Use the native dark mode" / Show All ▸ Interface ▸ Main
  interfaces ▸ macOS ▸ "Run VLC with dark interface style").

To hold the last frame at the end of a file (in the window, Syphon and NDI), turn on
Show All ▸ Playlist ▸ "Play and pause".

## Use

### Turn a plugin on or off

In VLC: **Preferences** ▸ **Show All** ▸ **Video** ▸ **Filters**, then tick **Syphon** and/or **NDI**.
Restart playback for the change to apply.

Or from the command line:

```sh
vlc --video-filter=syphon movie.mp4                         # Syphon
vlc --video-filter=ndi --audio-filter=ndi movie.mp4         # NDI, video and audio
vlc --video-filter=syphon:ndi --audio-filter=ndi movie.mp4  # both
```

NDI has a video filter and an audio filter. Turn on both for a source with sound: in
Preferences, also tick **NDI** under **Audio** ▸ **Filters**.

On macOS the VLC binary is `/Applications/VLC.app/Contents/MacOS/VLC`.

### Syphon options

In **Preferences** ▸ **Show All** ▸ **Video** ▸ **Filters** ▸ **Syphon**, or on the command line:

| Option | Default | |
|---|---|---|
| `--syphon-name` | `Video` | Server name shown in Syphon clients, e.g. "VLC – Video" |
| `--syphon-square-pixels` | on | Scale anamorphic video (e.g. DVDs) to its display aspect ratio |

Example: `vlc --video-filter=syphon --syphon-name="Stage Left" movie.mp4`.

### NDI options

In **Preferences** ▸ **Show All** ▸ **Video** ▸ **Filters** ▸ **NDI**, or on the command line:

| Option | Default | |
|---|---|---|
| `--ndi-name` | `VLC` | Source name. Receivers show "COMPUTER (VLC)" |
| `--ndi-bt709` | on | Convert SD and full-range colours to BT.709, which NDI receivers expect. Turn off if SD video looks wrong in your receiver |

### NDI needs the NDI Runtime

The NDI plugin needs only the free **NDI Runtime**, which you install yourself (it can't be
included here):

- **macOS:** [NDI Runtime for macOS](http://ndi.link/NDIRedistV6Apple) (`libNDI_for_Mac.pkg`, installs
  `/usr/local/lib/libndi.dylib`).
- **Windows:** [NDI 6 Runtime](http://ndi.link/NDIRedistV6).
- **Linux:** `libndi.so.6` from the NDI SDK, in your library path.

You don't need **NDI Tools**. Its apps (Studio Monitor, Video Monitor) are useful to view the
output, but on macOS installing them does not install the runtime.

Without it, VLC shows an error once and keeps playing without NDI. If the runtime is somewhere
unusual, set `NDI_RUNTIME_DIR_V6` to its folder.

On macOS, allow VLC to access the local network (and through the firewall) when it asks.

### Limitations

- Subtitles and VLC's on-screen messages are drawn after the filters, so they don't appear in the
  shared video.
- HDR video (HDR10, HLG) is shared without tone mapping and looks washed out.
- NDI sends video in 8 bits.

## Install the plugins into an existing VLC

For people who want to keep using the official VLC 3.0.x instead of the bundled apps.
Download the plugin zip for your platform from [Releases](https://github.com/rsodre/vlc-syphon-ndi/releases)
and unzip it.

**macOS:** the zip contains `libsyphon_plugin.dylib`, the NDI plugin and `Syphon.framework`.
Keep them together in one folder.

To keep the server/source up while nothing plays (as the apps do), also tick **Syphon** and/or
**NDI** in Preferences ▸ Show All ▸ Interface ▸ Control interfaces (or `--control=syphon:ndi`).
Without that they start with the first video, and then stay up until VLC quits.

- *Recommended:* leave VLC.app untouched and point VLC at the folder:

  ```sh
  mkdir -p "$HOME/Library/Application Support/vlc-syphon-ndi"
  cp -R plugins "$HOME/Library/Application Support/vlc-syphon-ndi/"
  open --env VLC_PLUGIN_PATH="$HOME/Library/Application Support/vlc-syphon-ndi/plugins" -a VLC
  ```

  You need to launch VLC this way each time. Tested from the command line; the `open` launch is not tested yet.
- *The usual VLC way:* copy everything into `VLC.app/Contents/MacOS/plugins/` (Finder:
  right-click VLC ▸ Show Package Contents). Recent macOS versions block this unless the app doing
  the copy has the **App Management** permission (System Settings ▸ Privacy & Security). It also breaks
  VLC's code signature, and every VLC update removes the plugins.

**Windows:** copy `lib*_plugin.dll` into `C:\Program Files\VideoLAN\VLC\plugins\video_filter\`,
then run `vlc --reset-plugins-cache` once. (Not tested yet.)

**Linux:** copy `lib*_plugin.so` into VLC's plugin folder (for example
`/usr/lib/x86_64-linux-gnu/vlc/plugins/video_filter/`), then run `vlc --reset-plugins-cache`.
(Not tested yet.)

## Build

You need CMake 3.24+, Ninja and a C compiler. Everything else (VLC headers, Syphon framework,
NDI headers) is already in `third_party/`. You don't need VLC installed to build.

**macOS** (Xcode or Command Line Tools; builds universal arm64 + x86_64):

```sh
cmake --preset macos
cmake --build --preset macos
# -> build/macos/out/plugins/lib*_plugin.dylib
```

**Linux:**

```sh
cmake --preset linux
cmake --build --preset linux
```

**Windows** with MinGW-w64 (MSYS2), or cross-compiled from Linux/macOS:

```sh
cmake --preset windows-mingw
cmake --build --preset windows-mingw
```

### Try it without installing

```sh
VLC_PLUGIN_PATH="$PWD/build/macos/out/plugins" /Applications/VLC.app/Contents/MacOS/VLC \
  --video-filter=syphon movie.mp4
```

### Test

These play generated clips in the installed VLC without modifying VLC.app. They need `ffmpeg`
to make the clips.

```sh
scripts/test-syphon-macos.sh       # Syphon end to end: size and colours, GPU and CPU paths
NDI_RUNTIME_DIR_V6=<NDI SDK>/lib/macOS scripts/test-ndi-macos.sh   # NDI: colours and A/V sync
scripts/test-load-macos.sh hello   # plugin loading smoke test (hello only logs)
build/macos/out/tools/syphon-probe --list   # list Syphon servers on this Mac
build/macos/out/tools/ndi-probe --list      # list NDI sources on the network
```

The NDI test needs the NDI runtime, installed or from the NDI SDK via `NDI_RUNTIME_DIR_V6`.

## Project structure

```
plugins/            one folder per VLC plugin, sources in src/
  hello/            test pass-through filter (not shipped)
  syphon/           Syphon filter (macOS)                    — works
  ndi/              NDI video + audio filters                — works on macOS
  spout/            Spout filter (Windows)                   — Phase 4, help wanted
shared/             code used by several plugins
  core/             protocol side, no VLC headers (frame description, ...)
  vlc3/             VLC 3.0.x adapter (VLC picture -> shared frame)
  ndi/              NDI runtime loader (plugin and ndi-probe)
tools/              developer test tools, sources in src/ (syphon-probe, ndi-probe: test clients)
apps/               the macOS apps: per-app config, launcher (src/), icons, packaging scripts
cmake/              CMake helpers (VLCPlugin.cmake), toolchains, build scripts
scripts/            developer scripts (vendoring VLC headers, tests)
third_party/        VLC 3.0.24 headers, Syphon.framework, NDI headers (see its README)
docs/               HANDOVER.md (architecture, plan), PHASE0.md, TESTING-APPS.md
```

## Distribution

Releases are published on GitHub: both macOS apps (DMGs), plugin zips, VLC's source and
checksums. The apps are the **official VLC** for macOS, unmodified, with our plugins and a tiny
launcher added. The launcher turns the app's default filters on at first launch. They are re-signed
with a Developer ID, notarized and stapled. Nothing in VLC is compiled.

```sh
apps/scripts/package-macos.sh 1     # build both apps locally (ad-hoc signed) into dist/
apps/scripts/release-macos.sh 1     # full release; signing needs SIGN_IDENTITY + NOTARY_PROFILE
```

Pushing a tag like `v3.0.24-1` runs the same in GitHub Actions and drafts the release.
How it works, signing setup and secrets: [apps/README.md](apps/README.md). Manual test
checklist: [docs/TESTING-APPS.md](docs/TESTING-APPS.md).
Details and status: [apps/README.md](apps/README.md) and [docs/HANDOVER.md](docs/HANDOVER.md).

To vendor headers for a new VLC release: `scripts/fetch-vlc-headers.sh 3.0.25`.

## Contributing

Pull requests are welcome, especially for:

- **Windows:** testing the NDI plugin, and the **Spout** plugin ([plugins/spout](plugins/spout/README.md)).
- **Linux:** testing and packaging the NDI plugin.

Please open an issue first for larger changes. Every source file needs the
`SPDX-License-Identifier: LGPL-2.1-or-later` header. Read [docs/HANDOVER.md](docs/HANDOVER.md)
for the architecture.

## License

[LGPL-2.1-or-later](LICENSE). Third-party files keep their own licenses
([third_party/README.md](third_party/README.md)). The bundled apps include VLC and are
distributed under the GPLv2. NDI® is a registered trademark of Vizrt NDI AB. Syphon is
BSD-licensed, by Tom Butterworth and Anton Marini.
