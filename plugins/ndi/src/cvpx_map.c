// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

#include <CoreVideo/CoreVideo.h>

#include "cvpx_map.h"

bool vsn_cvpx_mappable(vsn_pixfmt pixfmt)
{
    return pixfmt == VSN_PIXFMT_NV12 || pixfmt == VSN_PIXFMT_I420
        || pixfmt == VSN_PIXFMT_UYVY || pixfmt == VSN_PIXFMT_BGRA;
}

static bool layout(OSType type, vsn_pixfmt *fmt, unsigned *bpp)
{
    switch (type) {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
        *fmt = VSN_PIXFMT_NV12; bpp[0] = 1; bpp[1] = 2; return true;
    case kCVPixelFormatType_420YpCbCr8Planar:
    case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
        *fmt = VSN_PIXFMT_I420; bpp[0] = bpp[1] = bpp[2] = 1; return true;
    case kCVPixelFormatType_422YpCbCr8:
        *fmt = VSN_PIXFMT_UYVY; bpp[0] = 2; return true;
    case kCVPixelFormatType_32BGRA:
        *fmt = VSN_PIXFMT_BGRA; bpp[0] = 4; return true;
    default:
        return false;
    }
}

bool vsn_cvpx_map(const vsn_frame *frame, vsn_frame *cpu)
{
    CVPixelBufferRef pb = frame->native;
    unsigned bpp[3] = { 0 };
    vsn_pixfmt fmt;
    if (!pb || !layout(CVPixelBufferGetPixelFormatType(pb), &fmt, bpp))
        return false;
    if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess)
        return false;

    *cpu = *frame;
    cpu->pixfmt = fmt;
    cpu->memory = VSN_MEMORY_CPU;
    cpu->native = NULL;
    cpu->x_offset = cpu->y_offset = 0;
    switch (CVPixelBufferGetPixelFormatType(pb)) {  // the buffer knows its range best
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:
    case kCVPixelFormatType_420YpCbCr8PlanarFullRange:
        cpu->full_range = true; break;
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:
    case kCVPixelFormatType_420YpCbCr8Planar:
    case kCVPixelFormatType_422YpCbCr8:
        cpu->full_range = false; break;
    default: break;
    }

    size_t planes = CVPixelBufferGetPlaneCount(pb);
    size_t full_w = CVPixelBufferGetWidth(pb), full_h = CVPixelBufferGetHeight(pb);
    cpu->plane_count = planes ? (int)planes : 1;
    for (int i = 0; i < cpu->plane_count && i < 3; i++) {
        uint8_t *base = planes ? CVPixelBufferGetBaseAddressOfPlane(pb, i) : CVPixelBufferGetBaseAddress(pb);
        size_t stride = planes ? CVPixelBufferGetBytesPerRowOfPlane(pb, i) : CVPixelBufferGetBytesPerRow(pb);
        size_t w = planes ? CVPixelBufferGetWidthOfPlane(pb, i) : full_w;
        size_t h = planes ? CVPixelBufferGetHeightOfPlane(pb, i) : full_h;
        size_t x = frame->x_offset * w / full_w, y = frame->y_offset * h / full_h;
        cpu->planes[i].data = base + y * stride + x * bpp[i];
        cpu->planes[i].stride = (int)stride;
        cpu->planes[i].lines = (int)(h - y);
    }
    return true;
}

void vsn_cvpx_unmap(const vsn_frame *frame)
{
    CVPixelBufferUnlockBaseAddress((CVPixelBufferRef)frame->native, kCVPixelBufferLock_ReadOnly);
}
