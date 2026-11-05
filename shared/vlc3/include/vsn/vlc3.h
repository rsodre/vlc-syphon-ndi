// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// VLC 3.0.x adapter: VLC types -> vsn/frame.h.
// Include after <vlc_common.h>.

#ifndef VSN_VLC3_H
#define VSN_VLC3_H

#include <vlc_common.h>
#include <vlc_es.h>
#include <vlc_picture.h>

#include <vsn/frame.h>

/** Maps a VLC chroma to a pixel layout and memory kind. Returns false if unsupported. */
bool vsn_vlc3_chroma(vlc_fourcc_t chroma, vsn_pixfmt *pixfmt, vsn_memory *memory);

/**
 * Describes a VLC picture without copying it. Plane pointers stay valid only
 * while the picture is held. For CVPX (VideoToolbox) pictures, native is the
 * CVPixelBufferRef, not retained. For D3D11 pictures, native is left NULL (Phase 4).
 * Returns false if the chroma is unsupported.
 */
bool vsn_vlc3_frame_from_picture(const video_format_t *fmt, const picture_t *pic,
                                 vsn_frame *out);

/**
 * True if a VLC module list ("a:b{opt=1}:c", as in --video-filter) names module.
 * NULL or empty lists contain nothing.
 */
bool vsn_vlc3_list_has(const char *list, const char *module);

#endif
