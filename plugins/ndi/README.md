# ndi (macOS, Windows, Linux) — Phase 2, not started

Pass-through video filter (+ audio filter) that sends frames as an NDI® source.

Plan (see [docs/HANDOVER.md](../../docs/HANDOVER.md)):

- `src/` — module files (VLC 3 adapter) plus a VLC-agnostic NDI sender.
- CPU path: NDI accepts NV12 / I420 / UYVY directly. GPU frames are mapped to CPU first.
- `libndi` is **loaded at runtime** from the user's NDI Runtime (`Processing.NDI.DynamicLoad.h`).
  It is never linked or bundled. Missing runtime → clear error message, filter disabled.
- Compiles against the MIT-licensed headers in `third_party/ndi/include`.
