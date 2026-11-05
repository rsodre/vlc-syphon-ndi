// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// macOS: maps a VideoToolbox CVPixelBuffer frame to CPU planes, so it can be
// copied for NDI. No VLC types.

#ifndef VSN_NDI_CVPX_MAP_H
#define VSN_NDI_CVPX_MAP_H

#include <stdbool.h>

#include <vsn/frame.h>

/** True if a CVPixelBuffer frame of this layout can be mapped for NDI. */
bool vsn_cvpx_mappable(vsn_pixfmt pixfmt);

/**
 * Locks frame->native (a CVPixelBufferRef) for reading and fills cpu with plane
 * pointers to its visible area. Call vsn_cvpx_unmap() when done with cpu.
 */
bool vsn_cvpx_map(const vsn_frame *frame, vsn_frame *cpu);
void vsn_cvpx_unmap(const vsn_frame *frame);

#endif
