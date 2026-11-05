// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

#include <string.h>

#include <vsn/vlc3.h>

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

    if (out->memory != VSN_MEMORY_CPU)
        return true;

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
