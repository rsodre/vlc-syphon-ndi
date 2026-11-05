// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

#include <vsn/frame.h>

const char *vsn_pixfmt_name(vsn_pixfmt fmt)
{
    switch (fmt) {
    case VSN_PIXFMT_I420: return "I420";
    case VSN_PIXFMT_NV12: return "NV12";
    case VSN_PIXFMT_P010: return "P010";
    case VSN_PIXFMT_UYVY: return "UYVY";
    case VSN_PIXFMT_BGRA: return "BGRA";
    case VSN_PIXFMT_RGBA: return "RGBA";
    case VSN_PIXFMT_UNKNOWN: break;
    }
    return "unknown";
}

const char *vsn_colorspace_name(vsn_colorspace cs)
{
    switch (cs) {
    case VSN_COLORSPACE_BT601: return "BT.601";
    case VSN_COLORSPACE_BT709: return "BT.709";
    case VSN_COLORSPACE_BT2020: return "BT.2020";
    }
    return "unknown";
}

const char *vsn_memory_name(vsn_memory mem)
{
    switch (mem) {
    case VSN_MEMORY_CPU: return "cpu";
    case VSN_MEMORY_CVPIXELBUFFER: return "cvpixelbuffer";
    case VSN_MEMORY_D3D11: return "d3d11";
    }
    return "unknown";
}
