# Phase 0 – Feasibility test: results

Date: 2026-11-05. Machine: Apple Silicon, macOS 26.7.1, Xcode 27.2, official VLC 3.0.24
(universal, Developer ID `75GAHG3SZQ`, hardened runtime with `disable-library-validation`).

## What was built

- CMake superproject (`CMakeLists.txt`, `CMakePresets.json`, `cmake/VLCPlugin.cmake`).
- VLC 3.0.24 headers vendored from the official tarball (SHA-256 verified) in `third_party/vlc/3.0.24`.
- libvlccore is linked through a stub generated from `libvlccore.sym` (macOS: `.tbd`), so no VLC
  install is needed to build.
- `shared/` with `vsn::core` (VLC-agnostic `vsn_frame`) and `vsn::vlc3` (picture → frame adapter).
- `plugins/hello`: pass-through video filter that only logs.

The built `libhello_plugin.dylib` matches the official plugins: universal (arm64 + x86_64),
minimum macOS 11.0, depends on `@rpath/libvlccore.dylib` (compat 10.0.0), and exports
`vlc_entry__3_0_0f`, `vlc_entry_copyright__3_0_0f` and `vlc_entry_license__3_0_0f`.

## Results

| Test | Result |
|---|---|
| Build against vendored 3.0.24 headers, universal | **Pass**, no warnings |
| Load in official signed VLC.app via `VLC_PLUGIN_PATH` (bundle untouched) | **Pass** (`scripts/test-load-macos.sh`) |
| Hardware decoding (default) | **Pass**: filter receives `CVPN`, NV12 **CVPixelBuffer on the GPU** |
| Software decoding (`--codec=avcodec --avcodec-hw=none`) | **Pass**: `I420`, 3 CPU planes |
| Drop the plugin into `/Applications/VLC.app/Contents/MacOS/plugins` | **Blocked by macOS**: `cp: Operation not permitted` |
| Same drop-in on a copy of VLC.app | Inconclusive: the quarantined copy was SIGKILLed at launch even without our plugin, then became read-only (App Management) |
| Windows | Not tested yet (no Windows machine). CI cross-compiles with MinGW-w64. |
| Linux | Not tested yet. CI builds it. |

Without the filter, the official app's seal stays valid (`codesign --verify --deep --strict` passes).

### Why the drop-in is blocked

macOS (Ventura and later) has **App Management** protection: a process may not modify
another developer's signed app bundle unless the app hosting it (Terminal, iTerm, an installer)
has the *App Management* permission in System Settings ▸ Privacy & Security. Even with
that permission, the plugin breaks the bundle's seal (`a sealed resource is missing or invalid`).

To try it by hand, give your terminal App Management permission, then:

```sh
cp build/macos/out/plugins/libhello_plugin.dylib /Applications/VLC.app/Contents/MacOS/plugins/
PLUGIN_DIR= scripts/test-load-macos.sh hello
rm /Applications/VLC.app/Contents/MacOS/plugins/libhello_plugin.dylib   # restores the seal
```

## Conclusion: GO

The out-of-tree filter approach works with the unmodified official VLC 3.0.24, and GPU frames
reach the filter, so the Phase 1 zero-copy plan holds.

Consequences for distribution:

1. **The bundled apps (VLCSyphon.app, VLCNDI.app) are the main macOS deliverable.** We sign the
   whole bundle ourselves, so the seal and App Management problems don't arise.
2. **Plugin-only on macOS** works without touching VLC.app via `VLC_PLUGIN_PATH`. A user can
   launch the GUI with `open --env VLC_PLUGIN_PATH=<dir> -a VLC` (macOS 13+). A drop-in installer
   (`.pkg`) would also be possible, but it breaks VLC's seal and every VLC update erases it.
3. Plugin-only on Windows and Linux (drop into the plugins folder + `--reset-plugins-cache`) is
   still to be tested.

## Notes for Phase 1

- The CVPX picture context (`CVPixelBufferRef` inside `picture_t->context`) is defined in VLC's
  internal `modules/codec/vt_utils.c` (`struct cvpxpic_ctx`, first field after `picture_context_t`), not in the public headers. The Syphon plugin will need a
  small, documented mirror of that struct for 3.0.x.
- The filter is opened twice at start (VLC probes the chain, then rebuilds it), so `Open` must be
  cheap. Create the Syphon/NDI server lazily or reuse it.
