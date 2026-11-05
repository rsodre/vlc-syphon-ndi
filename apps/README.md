# Bundled apps — Phase 3, not started

Two signed and notarized apps, both based on VLC 3.0.24 and both containing **all**
plugins. They differ only in name, icon and which filter is on by default:

| App | Default `video-filter` | Icon |
|---|---|---|
| `VLCSyphon.app` | `syphon` | `resources/icons/VLCSyphon.icns` (orange) |
| `VLCNDI.app` | `ndi` | `resources/icons/VLCNDI.icns` (NDI blue) |

Users switch filters the regular VLC way (Preferences ▸ Video ▸ Filters, or
`--video-filter`). The default is a preference default, not a command-line argument,
so the user's own choice always wins.

- `resources/icons/` — `VLCSyphon.icns`/`.png` come from the legacy
  [rsodre/VLCSyphon](https://github.com/rsodre/VLCSyphon) repo. `VLCNDI.*` is generated
  from them by `scripts/make-icons.sh` (hue rotation).
- `scripts/` — packaging tooling. Signing uses the maintainer's Apple Developer ID and
  Apple's command-line tools (`codesign`, `notarytool`, `stapler`).

See [docs/HANDOVER.md](../docs/HANDOVER.md) ▸ Distribution for the build strategy.
