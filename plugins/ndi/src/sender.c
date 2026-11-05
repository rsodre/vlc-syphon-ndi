// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

#include <pthread.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#include <vsn/ndi_runtime.h>

#include "sender.h"

// Queue limits: beyond these, new frames are dropped rather than buffered.
#define MAX_QUEUED_VIDEO 30
#define MAX_QUEUED_AUDIO 400
// Frames more than this far in the future are treated as a clock jump and sent now.
#define MAX_DELAY_US 5000000
// NDI receivers only get frames sent after they connect, so when no new video comes
// (idle, paused, held last frame) the last video frame is sent again this often.
#define REPEAT_US 1000000
#define IDLE_WIDTH 1920
#define IDLE_HEIGHT 1080

typedef enum { ITEM_VIDEO, ITEM_AUDIO } item_kind;

typedef struct item {
    struct item *next;
    item_kind kind;
    bool idle;            // solid idle/clear frame: replaced by any newer video
    int64_t deadline_us;  // monotonic clock
    union {
        NDIlib_video_frame_v2_t video;
        NDIlib_audio_frame_interleaved_32f_t audio;
    };
    uint8_t data[];       // pixels or samples, pointed to by video.p_data / audio.p_data
} item;

struct vsn_ndi_sender {
    struct vsn_ndi_sender *next;  // registry
    char *name;
    unsigned refs;

    const NDIlib_v6 *ndi;
    NDIlib_send_instance_t instance;

    pthread_t thread;
    pthread_mutex_t lock;
    pthread_cond_t wake;
    bool quit;
    item *head;                   // sorted by deadline
    unsigned queued[2];           // per item_kind
    unsigned last_w, last_h;      // size of the last queued video frame
};

static pthread_mutex_t registry_lock = PTHREAD_MUTEX_INITIALIZER;
static vsn_ndi_sender *registry;

static int64_t mono_us(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (int64_t)ts.tv_sec * 1000000 + ts.tv_nsec / 1000;
}

static void wait_until(vsn_ndi_sender *s, int64_t deadline_us)
{
    // pthread_cond_timedwait uses the realtime clock (macOS has no condattr_setclock),
    // so convert the remaining monotonic time into a realtime deadline.
    int64_t remaining = deadline_us - mono_us();
    if (remaining <= 0)
        return;
    struct timespec ts;
    clock_gettime(CLOCK_REALTIME, &ts);
    int64_t ns = ts.tv_nsec + (remaining % 1000000) * 1000;
    ts.tv_sec += remaining / 1000000 + ns / 1000000000;
    ts.tv_nsec = ns % 1000000000;
    pthread_cond_timedwait(&s->wake, &s->lock, &ts);
}

static void *worker(void *opaque)
{
    vsn_ndi_sender *s = opaque;

    item *last = NULL;            // last video frame sent, repeated while nothing new comes
    int64_t last_sent = 0;

    pthread_mutex_lock(&s->lock);
    while (!s->quit) {
        item *it = s->head;
        if (!it) {
            if (!last) {
                pthread_cond_wait(&s->wake, &s->lock);
            } else if (mono_us() < last_sent + REPEAT_US) {
                wait_until(s, last_sent + REPEAT_US);  // may wake early for new frames
            } else {
                pthread_mutex_unlock(&s->lock);
                s->ndi->send_send_video_v2(s->instance, &last->video);
                last_sent = mono_us();
                pthread_mutex_lock(&s->lock);
            }
            continue;
        }
        if (it->deadline_us > mono_us() + 500) {
            wait_until(s, it->deadline_us);  // may wake early for a new head or quit
            continue;
        }
        s->head = it->next;
        s->queued[it->kind]--;
        pthread_mutex_unlock(&s->lock);

        // Both calls copy the data before returning.
        if (it->kind == ITEM_VIDEO) {
            s->ndi->send_send_video_v2(s->instance, &it->video);
            free(last);
            last = it;  // kept for repeats
            last_sent = mono_us();
        } else {
            s->ndi->util_send_send_audio_interleaved_32f(s->instance, &it->audio);
            free(it);
        }

        pthread_mutex_lock(&s->lock);
    }
    pthread_mutex_unlock(&s->lock);
    free(last);
    return NULL;
}

// Drops queued idle frames (a newer frame replaces them). Call with s->lock held.
static void drop_idle(vsn_ndi_sender *s)
{
    item **pp = &s->head;
    while (*pp) {
        item *it = *pp;
        if (it->idle) {
            *pp = it->next;
            s->queued[it->kind]--;
            free(it);
        } else {
            pp = &it->next;
        }
    }
}

static void drop_items(vsn_ndi_sender *s, bool video, bool audio)
{
    item **pp = &s->head;
    while (*pp) {
        item *it = *pp;
        if ((it->kind == ITEM_VIDEO && video) || (it->kind == ITEM_AUDIO && audio)) {
            *pp = it->next;
            s->queued[it->kind]--;
            free(it);
        } else {
            pp = &it->next;
        }
    }
}

static bool enqueue(vsn_ndi_sender *s, item *it, int64_t delay_us)
{
    if (delay_us < 0 || delay_us > MAX_DELAY_US)
        delay_us = 0;
    it->deadline_us = mono_us() + delay_us;

    pthread_mutex_lock(&s->lock);
    if (it->kind == ITEM_VIDEO) {
        drop_idle(s);  // video, or a newer idle frame, replaces a pending idle frame
        if (!it->idle) {
            s->last_w = (unsigned)it->video.xres;
            s->last_h = (unsigned)it->video.yres;
        }
    }
    unsigned limit = it->kind == ITEM_VIDEO ? MAX_QUEUED_VIDEO : MAX_QUEUED_AUDIO;
    if (s->queued[it->kind] >= limit) {
        pthread_mutex_unlock(&s->lock);
        free(it);
        return false;
    }
    // Insert in deadline order; frames almost always arrive in order, but audio
    // and video interleave.
    item **pp = &s->head;
    while (*pp && (*pp)->deadline_us <= it->deadline_us)
        pp = &(*pp)->next;
    it->next = *pp;
    *pp = it;
    s->queued[it->kind]++;
    if (s->head == it)
        pthread_cond_signal(&s->wake);
    pthread_mutex_unlock(&s->lock);
    return true;
}

// ---- Lifetime

static void sender_free(vsn_ndi_sender *s)
{
    if (s->instance) {
        pthread_mutex_lock(&s->lock);
        s->quit = true;
        pthread_cond_signal(&s->wake);
        pthread_mutex_unlock(&s->lock);
        pthread_join(s->thread, NULL);
        drop_items(s, true, true);
        s->ndi->send_destroy(s->instance);
    }
    pthread_cond_destroy(&s->wake);
    pthread_mutex_destroy(&s->lock);
    free(s->name);
    free(s);
}

vsn_ndi_sender *vsn_ndi_sender_acquire(const char *name, char *err, size_t err_size)
{
    if (!name)
        name = "";

    pthread_mutex_lock(&registry_lock);
    for (vsn_ndi_sender *s = registry; s; s = s->next) {
        if (!strcmp(s->name, name)) {
            s->refs++;
            pthread_mutex_unlock(&registry_lock);
            return s;
        }
    }

    vsn_ndi_sender *s = NULL;
    const NDIlib_v6 *ndi = vsn_ndi_load(err, err_size);
    if (!ndi)
        goto out;

    s = calloc(1, sizeof(*s));
    if (!s || !(s->name = strdup(name))) {
        snprintf(err, err_size, "out of memory");
        free(s);
        s = NULL;
        goto out;
    }
    s->refs = 1;
    s->ndi = ndi;
    pthread_mutex_init(&s->lock, NULL);
    pthread_cond_init(&s->wake, NULL);

    // We pace frames ourselves (worker thread), so NDI must not block on its clocks.
    NDIlib_send_create_t create = {
        .p_ndi_name = *name ? name : NULL,
        .p_groups = NULL,
        .clock_video = false,
        .clock_audio = false,
    };
    s->instance = ndi->send_create(&create);
    if (!s->instance) {
        snprintf(err, err_size, "could not create the NDI sender \"%s\"", name);
        sender_free(s);
        s = NULL;
        goto out;
    }
    if (pthread_create(&s->thread, NULL, worker, s) != 0) {
        snprintf(err, err_size, "could not start the NDI sender thread");
        ndi->send_destroy(s->instance);
        s->instance = NULL;
        sender_free(s);
        s = NULL;
        goto out;
    }
    s->next = registry;
    registry = s;
out:
    pthread_mutex_unlock(&registry_lock);
    return s;
}

void vsn_ndi_sender_release(vsn_ndi_sender *s)
{
    if (!s)
        return;
    pthread_mutex_lock(&registry_lock);
    bool last = --s->refs == 0;
    if (last) {
        for (vsn_ndi_sender **pp = &registry; *pp; pp = &(*pp)->next) {
            if (*pp == s) {
                *pp = s->next;
                break;
            }
        }
    }
    pthread_mutex_unlock(&registry_lock);
    if (last)
        sender_free(s);
}

bool vsn_ndi_sender_has_receivers(vsn_ndi_sender *s)
{
    return s->ndi->send_get_no_connections(s->instance, 0) > 0;
}

void vsn_ndi_sender_flush(vsn_ndi_sender *s, bool video, bool audio)
{
    pthread_mutex_lock(&s->lock);
    drop_items(s, video, audio);
    pthread_mutex_unlock(&s->lock);
}

// ---- Video

typedef struct ndi_layout {
    NDIlib_FourCC_video_type_e fourcc;
    size_t stride;   // bytes per luma (or packed) line
    size_t size;     // whole buffer
} ndi_layout;

static size_t align16(size_t n) { return (n + 15) & ~(size_t)15; }

static bool ndi_layout_for(const vsn_frame *f, ndi_layout *l)
{
    size_t w = f->width, h = f->height, ch = (h + 1) / 2;
    switch (f->pixfmt) {
    case VSN_PIXFMT_NV12:  // Y plane, then interleaved CbCr with the same stride
        l->fourcc = NDIlib_FourCC_video_type_NV12;
        l->stride = align16(2 * ((w + 1) / 2));
        l->size = l->stride * (h + ch);
        return true;
    case VSN_PIXFMT_I420:  // Y, then U and V planes with half the stride
        l->fourcc = NDIlib_FourCC_video_type_I420;
        l->stride = align16(2 * ((w + 1) / 2));
        l->size = l->stride * h + 2 * (l->stride / 2) * ch;
        return true;
    case VSN_PIXFMT_UYVY:
        l->fourcc = NDIlib_FourCC_video_type_UYVY;
        l->stride = align16(2 * w);
        l->size = l->stride * h;
        return true;
    case VSN_PIXFMT_BGRA:  // X: alpha is ignored, video frames are opaque
        l->fourcc = NDIlib_FourCC_video_type_BGRX;
        l->stride = 4 * w;
        l->size = l->stride * h;
        return true;
    case VSN_PIXFMT_RGBA:
        l->fourcc = NDIlib_FourCC_video_type_RGBX;
        l->stride = 4 * w;
        l->size = l->stride * h;
        return true;
    default:
        return false;
    }
}

bool vsn_ndi_supports(vsn_pixfmt pixfmt)
{
    vsn_frame f = { .pixfmt = pixfmt, .width = 2, .height = 2 };
    ndi_layout l;
    return ndi_layout_for(&f, &l);
}

static bool copy_plane(uint8_t *dst, size_t dst_stride, const vsn_plane *src,
                       size_t row_bytes, size_t rows)
{
    if (!src->data || (size_t)src->stride < row_bytes || (size_t)src->lines < rows)
        return false;
    for (size_t y = 0; y < rows; y++)
        memcpy(dst + y * dst_stride, src->data + y * (size_t)src->stride, row_bytes);
    return true;
}

// ---- Colour normalisation
//
// NDI receivers decode YUV as BT.709 limited range at every resolution (measured with
// the NDI 6.3.2 SDK receiver, although the docs say BT.601 for SD). Frames in another
// matrix or in full range are re-encoded to BT.709 limited range in place.
// Grey stays grey under this change, so chroma only depends on chroma (an exact 2x2
// transform per chroma sample), and luma gets a correction from its chroma sample.

typedef struct yuv_xform {
    float y_scale, y_off, y_cb, y_cr;  // Y' = y_scale * Y + y_off + y_cb * (Cb-128) + y_cr * (Cr-128)
    float cb_cb, cb_cr, cr_cb, cr_cr;  // C' = 128 + M * (C - 128)
} yuv_xform;

static void kr_kb(vsn_colorspace cs, float *kr, float *kb)
{
    switch (cs) {
    case VSN_COLORSPACE_BT709:  *kr = 0.2126f; *kb = 0.0722f; break;
    case VSN_COLORSPACE_BT2020: *kr = 0.2627f; *kb = 0.0593f; break;
    default:                    *kr = 0.299f;  *kb = 0.114f;  break;
    }
}

static yuv_xform make_xform(vsn_colorspace cs, bool full_range)
{
    // Source: codes -> normalized Y' (0..1) and Pb/Pr (-0.5..0.5).
    float ys = full_range ? 1.0f / 255 : 1.0f / 219, yo = full_range ? 0 : 16;
    float cs_ = full_range ? 1.0f / 255 : 1.0f / 224;
    float kr, kb, dkr, dkb;
    kr_kb(cs, &kr, &kb);
    kr_kb(VSN_COLORSPACE_BT709, &dkr, &dkb);
    float kg = 1 - kr - kb, dkg = 1 - dkr - dkb;

    // RGB = Y' + [0, a, b; c, d, 0] * (Pb, Pr) for the source matrix.
    float r_pr = 2 - 2 * kr, b_pb = 2 - 2 * kb;
    float g_pb = -b_pb * kb / kg, g_pr = -r_pr * kr / kg;
    // Destination Y' = dkr R + dkg G + dkb B; Pb = (B - Y') / (2 - 2 dkb); Pr = (R - Y') / (2 - 2 dkr).
    // With R,G,B = Y' + linear(Pb, Pr), Y'_dst = Y' + ly_pb Pb + ly_pr Pr.
    float ly_pb = dkg * g_pb + dkb * b_pb;
    float ly_pr = dkr * r_pr + dkg * g_pr;
    float pb_pb = (b_pb - ly_pb) / (2 - 2 * dkb), pb_pr = (-ly_pr) / (2 - 2 * dkb);
    float pr_pb = (-ly_pb) / (2 - 2 * dkr),       pr_pr = (r_pr - ly_pr) / (2 - 2 * dkr);

    // Back to BT.709 limited codes: Y = 16 + 219 Y', C = 128 + 224 P.
    yuv_xform x = {
        .y_scale = 219 * ys,
        .y_off = 16 - 219 * ys * yo,
        .y_cb = 219 * ly_pb * cs_,
        .y_cr = 219 * ly_pr * cs_,
        .cb_cb = 224 * pb_pb * cs_, .cb_cr = 224 * pb_pr * cs_,
        .cr_cb = 224 * pr_pb * cs_, .cr_cr = 224 * pr_pr * cs_,
    };
    return x;
}

static uint8_t clamp8(float v)
{
    return v <= 0 ? 0 : v >= 255 ? 255 : (uint8_t)(v + 0.5f);
}

static inline void xform_chroma(const yuv_xform *x, uint8_t *cb, uint8_t *cr)
{
    float u = *cb - 128.0f, v = *cr - 128.0f;
    *cb = clamp8(128 + x->cb_cb * u + x->cb_cr * v);
    *cr = clamp8(128 + x->cr_cb * u + x->cr_cr * v);
}

static inline uint8_t xform_luma(const yuv_xform *x, uint8_t y, uint8_t cb, uint8_t cr)
{
    return clamp8(x->y_scale * y + x->y_off + x->y_cb * (cb - 128.0f) + x->y_cr * (cr - 128.0f));
}

// Converts the NDI buffer in place. Luma first (it reads the original chroma).
static void to_bt709(uint8_t *buf, NDIlib_FourCC_video_type_e fourcc, size_t stride,
                     size_t w, size_t h, const yuv_xform *x)
{
    size_t cw = (w + 1) / 2, ch = (h + 1) / 2;
    if (fourcc == NDIlib_FourCC_video_type_UYVY) {
        for (size_t j = 0; j < h; j++) {
            uint8_t *p = buf + j * stride;
            for (size_t i = 0; i + 1 < 2 * w; i += 4) {
                uint8_t u = p[i], v = p[i + 2];
                p[i + 1] = xform_luma(x, p[i + 1], u, v);
                p[i + 3] = xform_luma(x, p[i + 3], u, v);
                xform_chroma(x, &p[i], &p[i + 2]);
            }
        }
        return;
    }
    uint8_t *y = buf;
    bool nv12 = fourcc == NDIlib_FourCC_video_type_NV12;
    size_t cstride = nv12 ? stride : stride / 2;
    uint8_t *c0 = buf + stride * h;              // NV12: CbCr; I420: Cb
    uint8_t *c1 = nv12 ? NULL : c0 + cstride * ch;  // I420: Cr
    for (size_t j = 0; j < h; j++) {
        uint8_t *row = y + j * stride;
        const uint8_t *cb_row = c0 + (j / 2) * cstride;
        const uint8_t *cr_row = nv12 ? cb_row + 1 : c1 + (j / 2) * cstride;
        size_t step = nv12 ? 2 : 1;
        for (size_t i = 0; i < w; i++)
            row[i] = xform_luma(x, row[i], cb_row[(i / 2) * step], cr_row[(i / 2) * step]);
    }
    for (size_t j = 0; j < ch; j++) {
        uint8_t *cb = c0 + j * cstride;
        uint8_t *cr = nv12 ? cb + 1 : c1 + j * cstride;
        size_t step = nv12 ? 2 : 1;
        for (size_t i = 0; i < cw; i++)
            xform_chroma(x, &cb[i * step], &cr[i * step]);
    }
}

bool vsn_ndi_sender_video(vsn_ndi_sender *s, const vsn_frame *f, int64_t delay_us,
                          bool to_709, char *err, size_t err_size)
{
    ndi_layout l;
    if (f->memory != VSN_MEMORY_CPU || !ndi_layout_for(f, &l) || !f->width || !f->height) {
        snprintf(err, err_size, "unsupported frame %s in %s memory",
                 vsn_pixfmt_name(f->pixfmt), vsn_memory_name(f->memory));
        return false;
    }
    item *it = malloc(sizeof(*it) + l.size);
    if (!it) {
        snprintf(err, err_size, "out of memory");
        return false;
    }
    it->kind = ITEM_VIDEO;
    it->idle = false;

    size_t w = f->width, h = f->height, cw = (w + 1) / 2, ch = (h + 1) / 2;
    uint8_t *y = it->data;
    bool ok;
    switch (f->pixfmt) {
    case VSN_PIXFMT_NV12:
        ok = f->plane_count >= 2
          && copy_plane(y, l.stride, &f->planes[0], w, h)
          && copy_plane(y + l.stride * h, l.stride, &f->planes[1], 2 * cw, ch);
        break;
    case VSN_PIXFMT_I420: {
        uint8_t *u = y + l.stride * h, *v = u + (l.stride / 2) * ch;
        ok = f->plane_count >= 3
          && copy_plane(y, l.stride, &f->planes[0], w, h)
          && copy_plane(u, l.stride / 2, &f->planes[1], cw, ch)
          && copy_plane(v, l.stride / 2, &f->planes[2], cw, ch);
        break;
    }
    case VSN_PIXFMT_UYVY:
        ok = f->plane_count >= 1 && copy_plane(y, l.stride, &f->planes[0], 2 * w, h);
        break;
    default:  // BGRA, RGBA
        ok = f->plane_count >= 1 && copy_plane(y, l.stride, &f->planes[0], 4 * w, h);
        break;
    }
    if (!ok) {
        free(it);
        snprintf(err, err_size, "frame planes are smaller than %ux%u", f->width, f->height);
        return false;
    }

    bool yuv = f->pixfmt == VSN_PIXFMT_NV12 || f->pixfmt == VSN_PIXFMT_I420
            || f->pixfmt == VSN_PIXFMT_UYVY;
    if (to_709 && yuv && (f->colorspace != VSN_COLORSPACE_BT709 || f->full_range)) {
        yuv_xform x = make_xform(f->colorspace, f->full_range);
        to_bt709(it->data, l.fourcc, l.stride, w, h, &x);
    }

    double aspect = (double)f->width * (f->sar_num ? f->sar_num : 1)
                  / ((double)f->height * (f->sar_den ? f->sar_den : 1));
    it->video = (NDIlib_video_frame_v2_t){
        .xres = (int)f->width,
        .yres = (int)f->height,
        .FourCC = l.fourcc,
        .frame_rate_N = f->fps_num && f->fps_den ? (int)f->fps_num : 30000,
        .frame_rate_D = f->fps_num && f->fps_den ? (int)f->fps_den : 1001,
        .picture_aspect_ratio = (float)aspect,
        .frame_format_type = NDIlib_frame_format_type_progressive,
        .timecode = NDIlib_send_timecode_synthesize,
        .p_data = it->data,
        .line_stride_in_bytes = (int)l.stride,
        .p_metadata = NULL,
        .timestamp = 0,
    };
    if (!enqueue(s, it, delay_us)) {
        snprintf(err, err_size, "send queue full, frame dropped");
        return false;
    }
    return true;
}

// ---- Audio

bool vsn_ndi_sender_audio(vsn_ndi_sender *s, const float *samples, unsigned channels,
                          unsigned frames, unsigned rate, int64_t delay_us)
{
    if (!channels || !frames || !rate)
        return true;
    size_t bytes = (size_t)channels * frames * sizeof(float);
    item *it = malloc(sizeof(*it) + bytes);
    if (!it)
        return false;
    it->kind = ITEM_AUDIO;
    it->idle = false;
    memcpy(it->data, samples, bytes);
    it->audio = (NDIlib_audio_frame_interleaved_32f_t){
        .sample_rate = (int)rate,
        .no_channels = (int)channels,
        .no_samples = (int)frames,
        .timecode = NDIlib_send_timecode_synthesize,
        .p_data = (float *)it->data,
    };
    return enqueue(s, it, delay_us);
}

// ---- Idle frames

void vsn_ndi_sender_set_size(vsn_ndi_sender *s, unsigned width, unsigned height)
{
    pthread_mutex_lock(&s->lock);
    s->last_w = width;
    s->last_h = height;
    pthread_mutex_unlock(&s->lock);
}

static bool queue_solid(vsn_ndi_sender *s, unsigned w, unsigned h, uint8_t r, uint8_t g,
                        uint8_t b, uint8_t a, int64_t delay_us)
{
    if (!w || !h) {
        pthread_mutex_lock(&s->lock);
        w = s->last_w ? s->last_w : IDLE_WIDTH;
        h = s->last_h ? s->last_h : IDLE_HEIGHT;
        pthread_mutex_unlock(&s->lock);
    }
    size_t bytes = (size_t)w * h * 4;
    item *it = malloc(sizeof(*it) + bytes);
    if (!it)
        return false;
    it->kind = ITEM_VIDEO;
    it->idle = true;
    for (size_t i = 0; i < bytes; i += 4) {
        it->data[i] = b;
        it->data[i + 1] = g;
        it->data[i + 2] = r;
        it->data[i + 3] = a;
    }
    it->video = (NDIlib_video_frame_v2_t){
        .xres = (int)w,
        .yres = (int)h,
        .FourCC = a == 255 ? NDIlib_FourCC_video_type_BGRX : NDIlib_FourCC_video_type_BGRA,
        .frame_rate_N = 30000,
        .frame_rate_D = 1001,
        .picture_aspect_ratio = (float)w / (float)h,
        .frame_format_type = NDIlib_frame_format_type_progressive,
        .timecode = NDIlib_send_timecode_synthesize,
        .p_data = it->data,
        .line_stride_in_bytes = (int)(4 * w),
    };
    return enqueue(s, it, delay_us);
}

void vsn_ndi_sender_color(vsn_ndi_sender *s, unsigned width, unsigned height,
                          uint8_t r, uint8_t g, uint8_t b, uint8_t a)
{
    queue_solid(s, width, height, r, g, b, a, 0);
}

void vsn_ndi_sender_clear_later(vsn_ndi_sender *s, unsigned delay_ms)
{
    queue_solid(s, 0, 0, 0, 0, 0, 0, (int64_t)delay_ms * 1000);
}
