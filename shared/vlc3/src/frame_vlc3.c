// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

#include <string.h>

#include <vsn/vlc3.h>

#ifdef __APPLE__
// Mirror of the head of VLC 3.0.x's private `struct cvpxpic_ctx`
// (modules/codec/vt_utils.c), which every CVPX picture carries as its context.
// VLC's own accessor, cvpxpic_get_ref(), is not exported to plugins.
// Re-check this layout whenever the vendored VLC version changes.
struct vsn_vlc3_cvpxpic_ctx {
    picture_context_t s;
    void *cvpx; // CVPixelBufferRef
};

static void *cvpx_from_picture(const picture_t *pic)
{
    if (!pic->context)
        return NULL;
    return ((const struct vsn_vlc3_cvpxpic_ctx *)pic->context)->cvpx;
}
#endif

bool vsn_vlc3_chroma(vlc_fourcc_t chroma, vsn_pixfmt *pixfmt, vsn_memory *memory)
{
    vsn_memory mem = VSN_MEMORY_CPU;
    vsn_pixfmt fmt;

    switch (chroma) {
    case VLC_CODEC_I420:      fmt = VSN_PIXFMT_I420; break;
    case VLC_CODEC_NV12:      fmt = VSN_PIXFMT_NV12; break;
    case VLC_CODEC_P010:      fmt = VSN_PIXFMT_P010; break;
    case VLC_CODEC_UYVY:      fmt = VSN_PIXFMT_UYVY; break;
    case VLC_CODEC_BGRA:      fmt = VSN_PIXFMT_BGRA; break;
    case VLC_CODEC_RGBA:      fmt = VSN_PIXFMT_RGBA; break;

    case VLC_CODEC_CVPX_I420: fmt = VSN_PIXFMT_I420; mem = VSN_MEMORY_CVPIXELBUFFER; break;
    case VLC_CODEC_CVPX_NV12: fmt = VSN_PIXFMT_NV12; mem = VSN_MEMORY_CVPIXELBUFFER; break;
    case VLC_CODEC_CVPX_P010: fmt = VSN_PIXFMT_P010; mem = VSN_MEMORY_CVPIXELBUFFER; break;
    case VLC_CODEC_CVPX_UYVY: fmt = VSN_PIXFMT_UYVY; mem = VSN_MEMORY_CVPIXELBUFFER; break;
    case VLC_CODEC_CVPX_BGRA: fmt = VSN_PIXFMT_BGRA; mem = VSN_MEMORY_CVPIXELBUFFER; break;

    case VLC_CODEC_D3D11_OPAQUE:     fmt = VSN_PIXFMT_NV12; mem = VSN_MEMORY_D3D11; break;
    case VLC_CODEC_D3D11_OPAQUE_10B: fmt = VSN_PIXFMT_P010; mem = VSN_MEMORY_D3D11; break;

    default:
        return false;
    }
    if (pixfmt) *pixfmt = fmt;
    if (memory) *memory = mem;
    return true;
}

bool vsn_vlc3_frame_from_picture(const video_format_t *fmt, const picture_t *pic,
                                 vsn_frame *out)
{
    memset(out, 0, sizeof(*out));
    if (!vsn_vlc3_chroma(fmt->i_chroma, &out->pixfmt, &out->memory))
        return false;

    out->width = fmt->i_visible_width;
    out->height = fmt->i_visible_height;
    out->sar_num = fmt->i_sar_num ? fmt->i_sar_num : 1;
    out->sar_den = fmt->i_sar_den ? fmt->i_sar_den : 1;
    out->fps_num = fmt->i_frame_rate;
    out->fps_den = fmt->i_frame_rate_base;
    out->pts_us = pic->date;
    out->x_offset = fmt->i_x_offset;
    out->y_offset = fmt->i_y_offset;
    out->full_range = fmt->b_color_range_full;
    switch (fmt->space) {
    case COLOR_SPACE_BT601:  out->colorspace = VSN_COLORSPACE_BT601; break;
    case COLOR_SPACE_BT709:  out->colorspace = VSN_COLORSPACE_BT709; break;
    case COLOR_SPACE_BT2020: out->colorspace = VSN_COLORSPACE_BT2020; break;
    default: // same guess as VLC's video_format_FixColorspace(): HD is BT.709
        out->colorspace = fmt->i_visible_height > 576 ? VSN_COLORSPACE_BT709
                                                      : VSN_COLORSPACE_BT601;
        break;
    }

    if (out->memory == VSN_MEMORY_CVPIXELBUFFER) {
#ifdef __APPLE__
        out->native = cvpx_from_picture(pic);
#endif
        return out->native != NULL;
    }
    if (out->memory != VSN_MEMORY_CPU)
        return true;

    out->x_offset = out->y_offset = 0;

    // Point each plane at the visible area. Chroma planes are subsampled, so the
    // offsets are scaled by the plane's size relative to the luma plane.
    const vlc_chroma_description_t *desc = vlc_fourcc_GetChromaDescription(fmt->i_chroma);
    if (!desc)
        return false;

    out->plane_count = pic->i_planes < VSN_MAX_PLANES ? pic->i_planes : VSN_MAX_PLANES;
    for (int i = 0; i < out->plane_count; i++) {
        const plane_t *p = &pic->p[i];
        unsigned x = fmt->i_x_offset * desc->p[i].w.num / desc->p[i].w.den;
        unsigned y = fmt->i_y_offset * desc->p[i].h.num / desc->p[i].h.den;
        out->planes[i].data = p->p_pixels + (size_t)y * p->i_pitch + (size_t)x * p->i_pixel_pitch;
        out->planes[i].stride = p->i_pitch;
        out->planes[i].lines = p->i_visible_lines;
    }
    return true;
}
