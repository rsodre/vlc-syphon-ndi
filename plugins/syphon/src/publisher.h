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
} vsn_syphon_config;

/* All functions are thread-safe. */

/** Returns NULL and writes a message to err on failure. */
vsn_syphon *vsn_syphon_create(const vsn_syphon_config *cfg, char *err, size_t err_size);

/** True if pixfmt + memory can be published (otherwise the host should convert first). */
bool vsn_syphon_supports(vsn_pixfmt pixfmt, vsn_memory memory);

/** True if at least one Syphon client is connected. */
bool vsn_syphon_has_clients(vsn_syphon *s);

/**
 * Converts and publishes one frame. GPU work is asynchronous; the frame's memory
 * is only read during this call (CPU) or retained until the GPU is done (CVPixelBuffer).
 * With square_pixels, non-square-pixel video is scaled to its display aspect.
 * Cancels a pending vsn_syphon_clear_later(). Returns false and writes to err on failure.
 */
bool vsn_syphon_publish(vsn_syphon *s, const vsn_frame *frame, bool square_pixels,
                        char *err, size_t err_size);

/**
 * Publishes a solid colour (components 0..1, straight alpha). width/height 0 means the
 * size last published (1920x1080 before anything was). Cancels a pending clear.
 */
void vsn_syphon_publish_color(vsn_syphon *s, unsigned width, unsigned height,
                              float r, float g, float b, float a);

/**
 * Publishes a solid colour at the last size after delay_ms, unless another frame is
 * published first. Used when video stops, so a quick restart doesn't flash.
 */
void vsn_syphon_clear_later(vsn_syphon *s, unsigned delay_ms, float r, float g, float b, float a);

/** Renames the server. */
void vsn_syphon_set_name(vsn_syphon *s, const char *name);

/** Waits for pending GPU work, stops the server and frees everything. */
void vsn_syphon_destroy(vsn_syphon *s);

#ifdef __cplusplus
}
#endif

#endif
