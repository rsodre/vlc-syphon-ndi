# spout (Windows) — Phase 4, contributions welcome

Pass-through video filter that shares frames through a Spout2 DirectX 11 sender.

Plan (see [docs/HANDOVER.md](../../docs/HANDOVER.md)):

- `src/` — module file (VLC 3 adapter) plus a VLC-agnostic Spout sender.
- Zero copy for Direct3D 11 hardware-decoded frames (`DX11` / `DX10` chromas).
- Spout2: https://github.com/leadedge/Spout2 (BSD-2-Clause).

If you want to work on this, open an issue first so we can agree on the approach.
