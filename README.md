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

> **Status:** first release, **v3.0.24-1** (macOS and Windows). Syphon (macOS) and NDI (macOS,
> Windows) work with VLC 3.0.24. The NDI plugin also compiles for Linux but is untested there,
> and Spout (Windows) is planned: [contributions welcome](#contributing).

## Requirements

| | macOS | Windows | Linux |
|---|---|---|---|
| **VLCSyphon.app** | macOS 11 Big Sur or later, Apple Silicon or Intel (universal app) | — | — |
| **VLCNDI** (app) | macOS 11 Big Sur or later, Apple Silicon or Intel (universal app) | Windows 10 or later, 64-bit | — |
| **Syphon plugin** | macOS 11 or later, Apple Silicon or Intel, with VLC 3.0.x | — | — |
| **NDI plugin** | macOS 13 Ventura or later (required by the current NDI 6 runtime) | Windows 10 or later, with the 64-bit VLC 3.0.x | planned, x86_64 |
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

Get the latest release from [GitHub Releases](https://github.com/rsodre/vlc-syphon-ndi/releases/latest):

| File (v3.0.24-1) | System | What it is |
|---|---|---|
| **`VLCSyphon-3.0.24-1.dmg`** | macOS 11+, Apple Silicon and Intel | VLCSyphon.app: VLC 3.0.24 with all plugins installed, **Syphon on** by default |
| **`VLCNDI-3.0.24-1.dmg`** | macOS 11+, Apple Silicon and Intel | VLCNDI.app: VLC 3.0.24 with all plugins installed, **NDI on** by default |
| **`VLCNDI-3.0.24-1-win64.zip`** | Windows 10+, 64-bit | VLCNDI for Windows: VLC 3.0.24 with the NDI plugin installed, **NDI on** by default |
| `vlc-syphon-ndi-plugins-macos-3.0.24-1.zip` | macOS | Just the plugins, to add to the official VLC ([install](#install-the-plugins-into-an-existing-vlc)) |
| `vlc-syphon-ndi-plugins-windows-3.0.24-1.zip` | Windows | Just the NDI plugin, to add to the official 64-bit VLC ([install](#install-the-plugins-into-an-existing-vlc)) |
| `vlc-3.0.24.tar.xz`, `SHA256SUMS` | | VLC's source code (GPL) and the files' checksums |

The macOS apps and plugins are signed by Studio Avante LTDA and notarized by Apple. The Windows
files are **not signed**: Windows SmartScreen may say "Windows protected your PC" the first time
you run `VLCNDI.exe` (More info ▸ Run anyway).

Both apps are the official VLC with every plugin added, so you can turn Syphon and NDI on or
off in either one. Each app keeps its own settings, separate from the official VLC. They are
based on VLC but are not made or endorsed by VideoLAN, and they don't update themselves: get
new versions from Releases.

Install on **macOS**: open the DMG and drag the app to Applications. You can install both apps, and the
official VLC, side by side. Unlike the official VLC, the apps don't ask about album art and
metadata on first launch. Online metadata lookup stays off (VLC's default); turn it on in
Preferences ▸ Interface ▸ "Allow metadata network access".

Install on **Windows**: install the [NDI 6 Runtime](http://ndi.link/NDIRedistV6), unzip
`VLCNDI-3.0.24-1-win64.zip` somewhere you can save files (Documents or the Desktop, not Program
Files) and run **`VLCNDI.exe`** inside the `VLCNDI` folder. Nothing is installed: the app keeps
its settings in a `portable` folder next to it, separate from an installed VLC, and deleting the
`VLCNDI` folder removes everything. The first start takes a few seconds longer (VLC lists its
plugins). Allow it through Windows Firewall if asked, so receivers on the network can see it.
VLCNDI doesn't check for updates, and like the official VLC it asks before sending a crash report
to VideoLAN. While it runs, the taskbar shows VLC's own cone icon.

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
- **Dark interface** (Interface ▸ "Interface style": Dark). macOS only: VLC 3 for Windows has no
  dark style.

To hold the last frame at the end of a file (in the window, Syphon and NDI), turn on
Show All ▸ Playlist ▸ "Play and pause".

## Use

### Turn a plugin on or off

In VLC: **Preferences** ▸ **Show All** ▸ **Video** ▸ **Filters**, then tick **Syphon** and/or **NDI**
(for NDI sound, also **Audio** ▸ **Filters** ▸ **NDI**), and Save. In the apps the change applies
within a second, even to the video that's playing; no restart needed. Unticking stops the Syphon
server / NDI source. In the official VLC with the plugin zip, that needs the control interfaces
below; without them, changes apply from the next file.

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

On macOS, allow the app (VLCNDI, or VLC) to access the local network, and through the firewall,
when it asks.

### Limitations

- Subtitles and VLC's on-screen messages are drawn after the filters, so they don't appear in the
  shared video.
- HDR video (HDR10, HLG) is shared without tone mapping and looks washed out.
- NDI sends video in 8 bits.

## Install the plugins into an existing VLC

For people who want to keep using the official VLC 3.0.x instead of the bundled apps.
On macOS, download `vlc-syphon-ndi-plugins-macos-<version>.zip` from [Releases](https://github.com/rsodre/vlc-syphon-ndi/releases)
and unzip it. On Windows, download `vlc-syphon-ndi-plugins-windows-<version>.zip`. Linux plugins
aren't released yet: [build them](#build) from source.

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

  You need to launch VLC this way each time.
- *The usual VLC way:* copy everything into `VLC.app/Contents/MacOS/plugins/` (Finder:
  right-click VLC ▸ Show Package Contents). Recent macOS versions block this unless the app doing
  the copy has the **App Management** permission (System Settings ▸ Privacy & Security). It also breaks
  VLC's code signature, and every VLC update removes the plugins.

**Windows** (64-bit VLC 3.0.x only): copy `plugins\video_filter\libndi_plugin.dll` from the zip
into `C:\Program Files\VideoLAN\VLC\plugins\video_filter\` (needs administrator rights), then
refresh VLC's plugin list once, in a Command Prompt run as administrator:

```bat
"C:\Program Files\VideoLAN\VLC\vlc-cache-gen.exe" "C:\Program Files\VideoLAN\VLC\plugins"
```

Then tick **NDI** in Tools ▸ Preferences ▸ Show settings: All ▸ Video ▸ Filters and Audio ▸ Filters
(and Interface ▸ Control interfaces, to keep the source up while nothing plays), Save and restart
VLC. A VLC update removes the plugin: copy it again.

**Linux** (built from source, untested): copy `libndi_plugin.so` into VLC's plugin folder (for
example `/usr/lib/x86_64-linux-gnu/vlc/plugins/video_filter/`), then run `vlc --reset-plugins-cache`.

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

**Windows** with MinGW-w64, or cross-compiled from Linux/macOS. On Windows, run this in Git Bash
or MSYS2 with CMake, Ninja and a MinGW-w64 toolchain that targets **msvcrt** (as VLC 3 does) in
`PATH`: MSYS2's MINGW64 environment, or an `msvcrt` build of
[llvm-mingw](https://github.com/mstorsjo/llvm-mingw/releases). Not UCRT: the plugin must share
VLC's C runtime.

```sh
cmake --preset windows-mingw
cmake --build --preset windows-mingw
# -> build/windows-mingw/out/plugins/libndi_plugin.dll, out/apps/VLCNDI.exe
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
scripts/test-live-toggle-macos.sh  # enabling/disabling in Preferences applies live
scripts/test-load-macos.sh hello   # plugin loading smoke test (hello only logs)
build/macos/out/tools/syphon-probe --list   # list Syphon servers on this Mac
build/macos/out/tools/ndi-probe --list      # list NDI sources on the network
```

The NDI test needs the NDI runtime, installed or from the NDI SDK via `NDI_RUNTIME_DIR_V6`.

On Windows (Git Bash, with the NDI 6 Runtime installed and `ffmpeg` in `PATH`):

```sh
scripts/test-ndi-windows.sh        # NDI: colours and A/V sync, Direct3D 11 and software decoding
```

It downloads the official VLC zip into `build/` and plays in a copy with its own settings, so an
installed VLC isn't touched. VLC's video window opens during each case.

## Project structure

```
plugins/            one folder per VLC plugin, sources in src/
  hello/            test pass-through filter (not shipped)
  syphon/           Syphon filter (macOS)                    — works
  ndi/              NDI video + audio filters                — works on macOS and Windows
  spout/            Spout filter (Windows)                   — Phase 4, help wanted
shared/             code used by several plugins
  core/             protocol side, no VLC headers (frame description, ...)
  vlc3/             VLC 3.0.x adapter (VLC picture -> shared frame)
  ndi/              NDI runtime loader (plugin and ndi-probe)
tools/              developer test tools, sources in src/ (syphon-probe, ndi-probe: test clients)
apps/               the macOS and Windows apps: per-app config, launcher (src/), icons, packaging scripts
cmake/              CMake helpers (VLCPlugin.cmake), toolchains, build scripts
scripts/            developer scripts (vendoring VLC headers, tests)
third_party/        VLC 3.0.24 headers, Syphon.framework, NDI headers (see its README)
docs/               HANDOVER.md (architecture, plan), PHASE0.md, TESTING-APPS.md
```

## Distribution

Releases are published on GitHub: both macOS apps (DMGs), the macOS plugin zip, VLC's source
and checksums. The apps are the **official VLC** for macOS, unmodified, with our plugins and a tiny
launcher added. The launcher turns the app's default filters on at first launch. They are re-signed
with a Developer ID, notarized and stapled. Nothing in VLC is compiled.

Releases are built and published locally:

```sh
apps/scripts/package-macos.sh 1     # build both apps locally (ad-hoc signed) into dist/
apps/scripts/release-macos.sh 1     # signed + notarized release; needs SIGN_IDENTITY + NOTARY_PROFILE
apps/scripts/publish-release.sh 1   # tag v3.0.24-1 and create a draft GitHub release
```

How it works and the signing setup: [apps/README.md](apps/README.md). Manual test
checklist: [docs/TESTING-APPS.md](docs/TESTING-APPS.md).

VLCNDI for Windows is made the same way from VideoLAN's `vlc-3.0.24-win64.zip` (unmodified, plus
the NDI plugin and the `VLCNDI.exe` launcher), as a portable zip. It isn't signed. On a Windows PC
(Git Bash) or cross-built:

```sh
apps/scripts/release-windows.sh 1   # build, package and zip into dist/3.0.24-1/
apps/scripts/publish-windows.sh 1   # add the Windows files to the GitHub release v3.0.24-1
```
Details and status: [apps/README.md](apps/README.md) and [docs/HANDOVER.md](docs/HANDOVER.md).

To vendor headers for a new VLC release: `scripts/fetch-vlc-headers.sh 3.0.25`.

## Contributing

Pull requests are welcome, especially for:

- **Windows:** the **Spout** plugin ([plugins/spout](plugins/spout/README.md)), and a Direct3D 11 path
  for the NDI plugin (today VLC's own converters copy hardware-decoded frames to the CPU and back).
- **Linux:** testing and packaging the NDI plugin.

Please open an issue first for larger changes. Every source file needs the
`SPDX-License-Identifier: LGPL-2.1-or-later` header. Read [docs/HANDOVER.md](docs/HANDOVER.md)
for the architecture.

## License

[LGPL-2.1-or-later](LICENSE). Third-party files keep their own licenses
([third_party/README.md](third_party/README.md)). The bundled apps include VLC and are
distributed under the GPLv2. NDI® is a registered trademark of Vizrt NDI AB. Syphon is
BSD-licensed, by Tom Butterworth and Anton Marini.
