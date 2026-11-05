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

> **Status:** early development. The build system and loading in VLC 3.0.24 work
> ([Phase 0](docs/PHASE0.md)). The Syphon and NDI plugins themselves aren't written yet.

## Download

Coming soon, for macOS:

| App | What it is |
|---|---|
| **VLCSyphon.app** | VLC 3.0.24 with all plugins installed, **Syphon on** by default |
| **VLCNDI.app** | VLC 3.0.24 with all plugins installed, **NDI on** by default |

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

### NDI needs the NDI Runtime

The NDI plugin uses the free NDI Runtime, which you install yourself. It isn't included here.
Download **NDI Tools** or the runtime from <https://ndi.video/tools/>. Without it, the NDI filter
logs an error and does nothing. On macOS, allow VLC through the firewall when it asks.

### Limitations

Subtitles and VLC's on-screen messages are drawn after the filters, so they don't appear in the
shared video.

## Install the plugins into an existing VLC

For people who want to keep using the official VLC 3.0.x instead of the bundled apps.

**macOS:** recent macOS versions block changes inside `VLC.app`. Keep the plugins in their own
folder and point VLC at it:

```sh
open --env VLC_PLUGIN_PATH="$HOME/Library/Application Support/vlc-syphon-ndi/plugins" -a VLC
```

Verified from the command line in Phase 0; the GUI launch above is not tested yet.

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

### Test

`plugins/hello` is a test filter that only logs. This plays a generated 2-second clip through the
installed VLC with a filter, without modifying VLC.app (needs `ffmpeg` to make the clip):

```sh
scripts/test-load-macos.sh hello
```

## Project structure

```
plugins/            one folder per VLC plugin, sources in src/
  hello/            test pass-through filter (not shipped)
  syphon/           Syphon filter (macOS)                    — Phase 1
  ndi/              NDI video + audio filters                — Phase 2
  spout/            Spout filter (Windows)                   — Phase 4, help wanted
shared/             code used by several plugins
  core/             protocol side, no VLC headers (frame description, ...)
  vlc3/             VLC 3.0.x adapter (VLC picture -> shared frame)
apps/               the bundled macOS apps (VLCSyphon, VLCNDI): icons and packaging
cmake/              CMake helpers (VLCPlugin.cmake) and toolchains
scripts/            developer scripts (vendoring VLC headers, load tests)
third_party/        VLC 3.0.24 headers, Syphon.framework, NDI headers (see its README)
docs/               design notes: HANDOVER.md (architecture, plan), PHASE0.md
```

## Distribution

The macOS apps are VLC 3.0.24 built from source with a one-line change to the default video filter,
plus all our plugins, signed with a Developer ID, notarized with `notarytool` and packed as DMGs.
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
