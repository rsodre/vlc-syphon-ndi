// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// VLC-agnostic description of one video frame, handed from a host adapter
// (vsn/vlc3.h today, a VLC 4 adapter later) to protocol code (Syphon, NDI, Spout).
// Must not include any VLC header.

#ifndef VSN_FRAME_H
#define VSN_FRAME_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/** Pixel layout. Valid for both CPU and GPU-resident frames. */
typedef enum vsn_pixfmt {
    VSN_PIXFMT_UNKNOWN = 0,
    VSN_PIXFMT_I420,  /**< 8-bit planar Y, U, V (4:2:0) */
    VSN_PIXFMT_NV12,  /**< 8-bit Y plane + interleaved UV plane (4:2:0) */
    VSN_PIXFMT_P010,  /**< 10-bit in 16-bit words, Y + interleaved UV (4:2:0) */
    VSN_PIXFMT_UYVY,  /**< 8-bit packed 4:2:2 */
    VSN_PIXFMT_BGRA,  /**< 8-bit packed B, G, R, A */
    VSN_PIXFMT_RGBA,  /**< 8-bit packed R, G, B, A */
} vsn_pixfmt;

/** Where the pixels live. */
typedef enum vsn_memory {
    VSN_MEMORY_CPU = 0,        /**< planes[] are valid */
    VSN_MEMORY_CVPIXELBUFFER,  /**< macOS VideoToolbox frame; native is a CVPixelBufferRef */
    VSN_MEMORY_D3D11,          /**< Windows Direct3D 11 frame; native is an ID3D11Texture2D */
} vsn_memory;

#define VSN_MAX_PLANES 4

typedef struct vsn_plane {
    const uint8_t *data;  /**< first byte of the visible area */
    int stride;           /**< bytes per line */
    int lines;            /**< visible lines */
} vsn_plane;

typedef struct vsn_frame {
    vsn_pixfmt pixfmt;
    vsn_memory memory;
    unsigned width, height;    /**< visible size in pixels */
    unsigned sar_num, sar_den; /**< sample aspect ratio, 1:1 if unknown */
    unsigned fps_num, fps_den; /**< frame rate, 0/0 if unknown */
    int64_t pts_us;            /**< presentation time in microseconds, host clock */
    int plane_count;           /**< 0 unless memory == VSN_MEMORY_CPU */
    vsn_plane planes[VSN_MAX_PLANES];
    void *native;              /**< GPU handle, see vsn_memory */
} vsn_frame;

/** Short, stable name for logs ("NV12", "I420", ...). */
const char *vsn_pixfmt_name(vsn_pixfmt fmt);

/** Short, stable name for logs ("cpu", "cvpixelbuffer", ...). */
const char *vsn_memory_name(vsn_memory mem);

#ifdef __cplusplus
}
#endif

#endif
