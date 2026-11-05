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

/** Drops queued frames (after a seek). */
void vsn_ndi_sender_flush(vsn_ndi_sender *s, bool video, bool audio);

#ifdef __cplusplus
}
#endif

#endif
