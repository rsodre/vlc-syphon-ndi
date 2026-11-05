# Third-party files

Committed so that a clone builds with nothing else to download. Each directory keeps
its own license. Nothing here is LGPL code of ours.

| Path | What | License | How to update |
|---|---|---|---|
| `vlc/3.0.24/` | VLC plugin + libvlc headers, `libvlccore.sym`, from the official source tarball (`SOURCE.sha256`) | LGPL-2.1-or-later (`COPYING.LIB`) | `scripts/fetch-vlc-headers.sh <version>` |
| `syphon/darwin/Syphon.framework` | Syphon framework, universal (arm64 + x86_64), built from Syphon-Framework `main` (has `SyphonMetalServer`) | BSD-2-Clause (see `Headers/Syphon.h`) | Replace the framework with a newer universal build |
| `ndi/include/` | NDI SDK headers only (`Version.txt`: NDI 6.3.2) | MIT, per file header | Copy `include/` from a newer NDI SDK |

## What is never committed

The NDI runtime (`libndi.dylib`, `Processing.NDI.Lib.*.dll`, `libndi.so`), the rest of the
NDI SDK (binaries, docs, examples, license PDF) and anything else proprietary. The NDI
plugin loads the runtime the user installed from https://ndi.video/tools/ at run time.

## Sources

- VLC: https://download.videolan.org/pub/videolan/vlc/
- Syphon: https://github.com/Syphon/Syphon-Framework (tagged releases predate the Metal API and are x86_64 only, so use a build of `main`)
- NDI SDK: https://ndi.video/for-developers/ndi-sdk/
