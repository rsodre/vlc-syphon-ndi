# syphon (macOS)

Pass-through video filter that publishes every frame through a Syphon server, while
VLC keeps playing normally. Module name `syphon`.

## Options

| Option | Default | |
|---|---|---|
| `--syphon-name` | `Video` | Server name. Clients show it next to the app name, e.g. "VLC – Video". |
| `--syphon-square-pixels` | on | Scale non-square-pixel video (anamorphic DVDs, some broadcast) to its display aspect, e.g. 720×576 16:9 → 1024×576. Off publishes the stored size. |

Per-filter syntax also works: `--video-filter='syphon{name=Stage Left}'`.

## Lifetime

There is one server per VLC process, and it stays up while VLC is open:

| When | The server shows |
|---|---|
| VLC starts (filter enabled) | fully transparent, 1920×1080 |
| A file plays | its video, at its resolution |
| The file ends with Play and pause on | the last frame |
| The file ends otherwise, the video window closes, or Stop | fully transparent at the last size |
| VLC quits | the server goes away |

Starting at launch needs the plugin's **control interface** (module `syphon`, capability
`interface`): Preferences ▸ Interface ▸ Control interfaces ▸ Syphon, or `--control=syphon`. It does
nothing unless the Syphon video filter is enabled. Without it, the server starts with the first
video. The apps turn it on (`control=syphon:ndi`). The switch to transparent waits 300 ms, so
VLC rebuilding the filter chain between files doesn't flash.

The control interface also follows Preferences **live**: it checks the saved `video-filter`
setting twice a second. Enabling Syphon starts the server and adds the filter to the video that's
playing; disabling removes the filter and stops the server (VLC rebuilds the filter chain of a
running video when its `video-filter` variable changes, as the Video Effects panel does).
Test: `scripts/test-live-toggle-macos.sh syphon`.

## How it works

```
src/module.c      VLC 3 adapter: options, chroma negotiation, picture -> vsn_frame
src/publisher.h   C interface of the publisher (no VLC types)
src/publisher.m   Metal + SyphonMetalServer (ARC)
src/shaders.metal YCbCr/RGB -> BGRA shader, embedded into the plugin at build time
```

- The server is created on the first frame, not when the filter opens, because VLC opens and
  closes filters while it builds the chain.
- Frames are only converted while at least one Syphon client is connected.
- **GPU path (zero copy):** VideoToolbox frames (`CVPX` chromas) are wrapped as Metal textures
  through `CVMetalTextureCache`. The CVPixelBuffer handle comes from VLC's private picture
  context, mirrored in `shared/vlc3/src/frame_vlc3.c`.
- **CPU path:** software-decoded frames are copied into a ring of 3 upload textures.
- One shader pass converts to BGRA, crops to the visible area and applies the aspect correction.
  It handles BT.601/709/2020 matrices, limited and full range, 8 and 10 bit.
- Supported input: NV12, P010, I420, BGRA, RGBA (CPU or CVPixelBuffer). VLC converts anything
  else (4:2:2, 4:4:4, ...) before the filter.
- At most 3 frames are in flight on the GPU, so a slow GPU throttles the filter instead of
  queuing work.

## Linking

The plugin links `@rpath/Syphon.framework`, with rpaths `@loader_path` (framework next to the
plugin: plugin zips and `VLC_PLUGIN_PATH` folders) and `@loader_path/../../Frameworks`
(bundled apps: `Contents/MacOS/plugins` → `Contents/Frameworks`). The build copies the framework
next to the plugins in `build/<preset>/out/plugins/`.

## Testing

```sh
scripts/test-syphon-macos.sh            # all cases
scripts/test-syphon-macos.sh hw-709     # one case
```

Each case plays a generated four-colour clip in the installed VLC (not modified, plugins via
`VLC_PLUGIN_PATH`), grabs a frame with `tools/syphon-probe` and checks the size and colours.
Cases: hardware and software decoding, 1080p (cropped 1088-line buffers), anamorphic BT.601 SD,
full range, 10-bit HEVC (P010), and 4:2:2 (converted by VLC before the filter).

`build/macos/out/tools/syphon-probe --list` lists the Syphon servers running on the machine.

## Limitations

- HDR (PQ/HLG) video is not tone-mapped: it is published with its SDR matrix, so it looks
  washed out.
- Subtitles and on-screen messages are drawn after the filter, so they are not published.
- Frames are published when VLC prepares them, slightly before they appear on screen.
