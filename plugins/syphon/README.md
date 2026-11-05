# syphon (macOS) — Phase 1, not started

Pass-through video filter that publishes every frame through a Syphon **Metal** server.

Plan (see [docs/HANDOVER.md](../../docs/HANDOVER.md)):

- `src/` — module file (VLC 3 adapter) plus a VLC-agnostic Syphon publisher.
- VideoToolbox frames arrive as `CVPX` chromas (verified in Phase 0: `CVPN` = NV12 CVPixelBuffer).
  Keep them on the GPU: CVPixelBuffer → IOSurface/Metal texture → RGBA conversion → `SyphonMetalServer`.
- CPU fallback for software-decoded frames (`I420` etc.).
- Options: server name, enable.
- Links `third_party/syphon/darwin/Syphon.framework`.
