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

> **Status:** early development. The **Syphon** plugin works with VLC 3.0.24 on macOS
> (build it yourself for now, see [Build](#build)). NDI and the ready-made apps are next.

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
- **NDI:** the free [NDI Runtime](https://ndi.video/tools/) must be installed. A wired network is
  recommended for HD and above.

## Download

Everything will be on the [GitHub Releases](https://github.com/rsodre/vlc-syphon-ndi/releases) page
(coming soon):

| App | What it is |
|---|---|
| **VLCSyphon.app** | VLC 3.0.24 with all plugins installed, **Syphon on** by default |
| **VLCNDI.app** | VLC 3.0.24 with all plugins installed, **NDI on** by default |
| **Plugin zips** | Just the plugins, per platform, to add to the official VLC ([install](#install-the-plugins-into-an-existing-vlc)) |

Both apps contain every plugin, so you can turn Syphon and NDI on or off in either one.
They are based on VLC but are not made or endorsed by VideoLAN.

## Use

### Turn a plugin on or off

In VLC: **Preferences** ▸ **Show All** ▸ **Video** ▸ **Filters**, then tick **Syphon** and/or **NDI**.
Restart playback for the change to apply.

Or from the command line:

```sh
vlc --video-filter=syphon movie.mp4        # Syphon only
vlc --video-filter=ndi movie.mp4           # NDI only
vlc --video-filter=syphon:ndi movie.mp4    # both
```

On macOS the VLC binary is `/Applications/VLC.app/Contents/MacOS/VLC`.

### Syphon options

In **Preferences** ▸ **Show All** ▸ **Video** ▸ **Filters** ▸ **Syphon**, or on the command line:

| Option | Default | |
|---|---|---|
| `--syphon-name` | `Video` | Server name shown in Syphon clients, e.g. "VLC – Video" |
| `--syphon-square-pixels` | on | Scale anamorphic video (e.g. DVDs) to its display aspect ratio |

Example: `vlc --video-filter=syphon --syphon-name="Stage Left" movie.mp4`.

### NDI needs the NDI Runtime

The NDI plugin uses the free NDI Runtime, which you install yourself. It isn't included here.
Download **NDI Tools** or the runtime from <https://ndi.video/tools/>. Without it, the NDI filter
logs an error and does nothing. On macOS, allow VLC through the firewall when it asks.

### Limitations

- Subtitles and VLC's on-screen messages are drawn after the filters, so they don't appear in the
  shared video.
- HDR video (HDR10, HLG) is shared without tone mapping and looks washed out.

## Install the plugins into an existing VLC

For people who want to keep using the official VLC 3.0.x instead of the bundled apps.
Download the plugin zip for your platform from [Releases](https://github.com/rsodre/vlc-syphon-ndi/releases)
and unzip it.

**macOS:** the zip contains `libsyphon_plugin.dylib`, the NDI plugin and `Syphon.framework`.
Keep them together in one folder.

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
scripts/test-load-macos.sh hello   # plugin loading smoke test (hello only logs)
build/macos/out/tools/syphon-probe --list   # list Syphon servers on this Mac
```

## Project structure

```
plugins/            one folder per VLC plugin, sources in src/
  hello/            test pass-through filter (not shipped)
  syphon/           Syphon filter (macOS)                    — works
  ndi/              NDI video + audio filters                — Phase 2
  spout/            Spout filter (Windows)                   — Phase 4, help wanted
shared/             code used by several plugins
  core/             protocol side, no VLC headers (frame description, ...)
  vlc3/             VLC 3.0.x adapter (VLC picture -> shared frame)
tools/              developer test tools, sources in src/ (syphon-probe: Syphon test client)
apps/               the bundled macOS apps (VLCSyphon, VLCNDI): icons and packaging
cmake/              CMake helpers (VLCPlugin.cmake), toolchains, build scripts
scripts/            developer scripts (vendoring VLC headers, tests)
third_party/        VLC 3.0.24 headers, Syphon.framework, NDI headers (see its README)
docs/               design notes: HANDOVER.md (architecture, plan), PHASE0.md
```

## Distribution

Releases are published on GitHub with both macOS apps (DMGs) and plugin zips per platform.
The apps are VLC 3.0.24 built from source with a small patch that reads the default video filter
from the app's Info.plist, plus all our plugins. They are signed with a Developer ID, notarized with
`notarytool` and stapled.
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
