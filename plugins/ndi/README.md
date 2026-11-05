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

## NDI runtime

The NDI runtime is proprietary, so it is never bundled. Users install it from
<https://ndi.video/tools/>. The plugin loads it on the first frame, from:

1. `$NDI_RUNTIME_DIR_V6/` (set by the Windows installer; handy for testing with an SDK copy)
2. macOS: `/usr/local/lib/libndi.dylib`, `/Library/NDI SDK for Apple/lib/macOS/`;
   Linux: `libndi.so.6` on the library path, `/usr/local/lib`, `/usr/lib`;
   Windows: `Processing.NDI.Lib.x64.dll` on the DLL search path

If it isn't found, VLC shows an error once ("NDI 6 runtime not found … Install it from
https://ndi.video/tools/") and keeps playing without NDI.

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
