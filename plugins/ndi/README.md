# ndi (macOS; Windows and Linux to be tested)

Pass-through video **and** audio filters that send what VLC plays as an NDI® source,
while VLC keeps playing normally. Module name `ndi` in both filter lists:

```sh
vlc --video-filter=ndi --audio-filter=ndi movie.mp4
```

Both filters with the same `--ndi-name` feed one NDI source. Enable only the video filter
for a silent source, or only the audio filter for an audio-only source.

## Options

| Option | Default | |
|---|---|---|
| `--ndi-name` | `VLC` | Source name. Receivers show "COMPUTER (VLC)". |
| `--ndi-bt709` | on | Re-encode SD (BT.601), BT.2020 and full-range video to BT.709 limited range (see Colours). |

Per-filter syntax also works: `--video-filter='ndi{name=Screen 2}'`. Give both filters the
same name (`--ndi-name` sets it for both).

## Lifetime

The NDI source stays up while VLC is open:

| When | The source sends |
|---|---|
| VLC starts (filter enabled) | fully transparent, 1920×1080 |
| A file plays | its video, at its resolution |
| The file ends with Play and pause on | the last frame |
| The file ends otherwise, the video window closes, or Stop | fully transparent at the last size |
| VLC quits | the source goes away |

- Starting at launch needs the control interface `ndi` (Preferences ▸ Interface ▸ Control
  interfaces ▸ NDI, or `--control=ndi`). It does nothing unless an NDI filter is enabled.
- The control interface follows Preferences **live** (checks twice a second): enabling the video
  or audio filter adds it to what's playing (and starts the source); disabling both removes them
  and stops the source. Test: `scripts/test-live-toggle-macos.sh ndi`.
- NDI receivers only get frames sent after they connect, so the last video frame is sent again
  once a second while nothing new comes (idle, paused, held last frame). While no receiver is
  connected, one real frame a second is still sent, because NDI gives a new receiver the last
  frame sent.

## NDI runtime

The NDI runtime is proprietary, so it is never bundled. Users install only the runtime: on
macOS the [NDI Runtime for macOS](http://ndi.link/NDIRedistV6Apple) (`libNDI_for_Mac.pkg`), on Windows the
[NDI 6 Runtime](http://ndi.link/NDIRedistV6). NDI Tools is not needed (on macOS its apps embed private
copies and install no shared runtime). The plugin loads the runtime from:

1. `$NDI_RUNTIME_DIR_V6/` (set by the Windows installer; handy for testing with an SDK copy)
2. macOS: `/usr/local/lib/libndi.dylib`, `/Library/NDI SDK for Apple/lib/macOS/`;
   Linux: `libndi.so.6` on the library path, `/usr/local/lib`, `/usr/lib`;
   Windows: `Processing.NDI.Lib.x64.dll` on the DLL search path

If it isn't found, VLC shows an error once ("NDI Runtime not found. Install the NDI Runtime for
macOS (libNDI_for_Mac.pkg) from http://ndi.link/NDIRedistV6Apple, then restart.", naming the right
package on each platform) and keeps playing without NDI.

## How it works

```
src/module.c     VLC 3 adapter: video + audio filters, options, chroma negotiation
src/sender.h/.c  NDI sender, no VLC types: one per source name, worker thread, queue
src/cvpx_map.c   macOS: maps VideoToolbox CVPixelBuffers for reading
shared/ndi       runtime loader (also used by tools/ndi-probe)
```

- **Timing:** VLC hands audio to filters well ahead of video. Each frame is copied and queued
  with its presentation time, and a worker thread sends it at that moment. Measured A/V offset
  in receivers: about +14 ms (audio late), under half a frame at 30 fps.
- Nothing is copied while no receiver is connected.
- **Video formats:** NV12, I420, UYVY, BGRA, RGBA are sent as they are (BGRA/RGBA as BGRX/RGBX,
  opaque). VideoToolbox frames are mapped and copied on the CPU. Anything else (10-bit, 4:2:2
  planar, …) is converted by VLC before the filter.
- **Audio:** VLC converts to interleaved 32-bit float; it is sent at the source's rate and
  channel count.
- **Colours:** the NDI SDK documentation says receivers decode SD as BT.601, but the NDI 6.3.2
  receiver decodes every resolution as BT.709 limited range (measured). With `--ndi-bt709`, the
  sender re-encodes other matrices and full range to BT.709 limited range in the copy it already
  makes. BT.709 limited-range video (most HD) is untouched.
- Picture aspect ratio and frame rate are taken from the video, so anamorphic video displays correctly.
- Senders are created without NDI's clocking (`clock_video/audio = false`), so NDI never blocks
  VLC's threads.

## Testing

```sh
NDI_RUNTIME_DIR_V6=/path/to/NDI/SDK/lib/macOS scripts/test-ndi-macos.sh
```

Plays generated clips in the installed VLC (not modified) and receives them with `tools/ndi-probe`:
colours (HD and anamorphic SD, hardware and software decoding, full range) and A/V sync (a clip
that flashes white and beeps once a second; frame rate and flash-to-beep offset).
`build/macos/out/tools/ndi-probe --list` lists the NDI sources on the network.

## Limitations

- HDR video is not tone-mapped; 10-bit video is sent as 8-bit.
- Subtitles and on-screen messages are drawn after the filter, so they are not sent.
- Windows and Linux: the code is portable and CI builds it, but nothing has been compiled or run there yet.
