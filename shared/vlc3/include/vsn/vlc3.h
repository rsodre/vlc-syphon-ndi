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
 * while the picture is held. For GPU pictures, native is left NULL here:
 * extracting the handle is platform code (see plugins/syphon, plugins/spout).
 * Returns false if the chroma is unsupported.
 */
bool vsn_vlc3_frame_from_picture(const video_format_t *fmt, const picture_t *pic,
                                 vsn_frame *out);

#endif
