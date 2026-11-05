// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// NDI sender shared by the video and audio filters. No VLC types here;
// plugins/ndi/src/module.c is the VLC 3 adapter.
//
// One NDI source per name: the video and audio filters of the same VLC instance
// acquire the same sender, so receivers get one source with both.
//
// Frames are copied, queued and sent by a worker thread at their presentation time.
// VLC hands audio to filters well ahead of video, so sending on arrival would put
// them out of sync in receivers.

#ifndef VSN_NDI_SENDER_H
#define VSN_NDI_SENDER_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#include <vsn/frame.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vsn_ndi_sender vsn_ndi_sender;

/**
 * Returns the sender for name, creating it (and loading the NDI runtime) if needed.
 * Each successful call must be balanced by vsn_ndi_sender_release().
 * Returns NULL and writes a message to err on failure.
 */
vsn_ndi_sender *vsn_ndi_sender_acquire(const char *name, char *err, size_t err_size);
void vsn_ndi_sender_release(vsn_ndi_sender *s);

/** True if at least one NDI receiver is connected. */
bool vsn_ndi_sender_has_receivers(vsn_ndi_sender *s);

/** True if a CPU frame in this pixel format can be sent without conversion. */
bool vsn_ndi_supports(vsn_pixfmt pixfmt);

/**
 * Copies a CPU frame and queues it to be sent delay_us from now (its presentation
 * time; negative or zero means now). With to_bt709, YUV frames in another matrix or
 * in full range are re-encoded to BT.709 limited range, which is what NDI receivers
 * decode. Returns false and writes to err on failure.
 */
bool vsn_ndi_sender_video(vsn_ndi_sender *s, const vsn_frame *frame, int64_t delay_us,
                          bool to_bt709, char *err, size_t err_size);

/** Copies interleaved float samples and queues them like vsn_ndi_sender_video(). */
bool vsn_ndi_sender_audio(vsn_ndi_sender *s, const float *samples, unsigned channels,
                          unsigned frames, unsigned rate, int64_t delay_us);

/**
 * Sends a solid colour frame now (straight alpha; 255 = opaque). width/height 0 means
 * the size of the last video frame (1920x1080 before any). Replaces a pending idle frame.
 */
void vsn_ndi_sender_color(vsn_ndi_sender *s, unsigned width, unsigned height,
                          uint8_t r, uint8_t g, uint8_t b, uint8_t a);

/**
 * Sends a fully transparent frame at the last video size after delay_ms, unless video comes
 * first. Used when video stops, so a quick restart doesn't flash.
 */
void vsn_ndi_sender_clear_later(vsn_ndi_sender *s, unsigned delay_ms);

/*
 * Whatever video frame was sent last is sent again every second while nothing new comes,
 * because NDI receivers only get frames sent after they connect.
 */

/** Records the current video size (for idle frames) even when no frame is sent. */
void vsn_ndi_sender_set_size(vsn_ndi_sender *s, unsigned width, unsigned height);

/** Drops queued frames (after a seek). */
void vsn_ndi_sender_flush(vsn_ndi_sender *s, bool video, bool audio);

#ifdef __cplusplus
}
#endif

#endif
