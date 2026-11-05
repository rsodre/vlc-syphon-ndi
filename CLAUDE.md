# vlc-syphon-ndi

Out-of-tree VLC plugins that publish video frames over **Syphon** (macOS) and **NDI**
(cross-platform), with **Spout** (Windows) planned. They replace the old VLCSyphon fork.

**Start by reading `docs/HANDOVER.md`.** It covers the research, the architecture decision,
the licensing, the distribution plan and the phased to-do list.

## Key decisions (don't reopen without a reason)

- Pass-through **video filter** modules (`"video filter"` capability), built **out of tree**
  against VLC **3.0.x** headers (current release: 3.0.24). This is not a VLC fork.
- Protocol code is kept separate from the VLC API, so a VLC 4 adapter stays thin.
- Never bundle the NDI runtime. Load `libndi` at runtime from the user's NDI Runtime install.
- License: LGPL-2.1-or-later. Put an SPDX header in every source file.
- Universal macOS binaries (arm64 + x86_64).

## Reference

The legacy implementation is in `/Users/roger/Dev/XCode/VLCSyphon` (branch `Syphon`).
Look at `modules/video_output/syphonServer*.{h,m}`. Use it for reference only;
don't copy files from it into this repo.
