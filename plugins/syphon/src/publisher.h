// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// Syphon publisher: takes vsn_frame frames (CPU planes or CVPixelBuffers), converts
// them to BGRA on the GPU with Metal and publishes them through a SyphonMetalServer.
// No VLC types here; plugins/syphon/src/module.c is the VLC 3 adapter.

#ifndef VSN_SYPHON_PUBLISHER_H
#define VSN_SYPHON_PUBLISHER_H

#include <stdbool.h>
#include <stddef.h>

#include <vsn/frame.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vsn_syphon vsn_syphon;

typedef struct vsn_syphon_config {
    const char *name;    /**< server name shown in clients, may be NULL */
    bool square_pixels;  /**< scale non-square-pixel video to its display aspect */
} vsn_syphon_config;

/** Returns NULL and writes a message to err on failure. */
vsn_syphon *vsn_syphon_create(const vsn_syphon_config *cfg, char *err, size_t err_size);

/** True if pixfmt + memory can be published (otherwise the host should convert first). */
bool vsn_syphon_supports(vsn_pixfmt pixfmt, vsn_memory memory);

/** True if at least one Syphon client is connected. */
bool vsn_syphon_has_clients(vsn_syphon *s);

/**
 * Converts and publishes one frame. GPU work is asynchronous; the frame's memory
 * is only read during this call (CPU) or retained until the GPU is done (CVPixelBuffer).
 * Returns false and writes a message to err on failure.
 */
bool vsn_syphon_publish(vsn_syphon *s, const vsn_frame *frame, char *err, size_t err_size);

/** Waits for pending GPU work, stops the server and frees everything. */
void vsn_syphon_destroy(vsn_syphon *s);

#ifdef __cplusplus
}
#endif

#endif
