// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// Syphon publisher (see publisher.h). Compiled with ARC.
//
// Every frame is drawn into one BGRA texture by a small Metal shader that converts
// YCbCr to RGB, crops to the visible area and optionally corrects the pixel aspect.
// That texture is handed to SyphonMetalServer on the same command buffer.
// Our texture has its top row first (Metal's usual layout). Syphon frames follow the
// OpenGL convention (first row = bottom of the picture), so frames are published with
// flipped:YES; with NO, OpenGL clients such as Simple Client showed them upside down.
//
//   CVPixelBuffer (VideoToolbox)  -> CVMetalTextureCache, zero copy
//   CPU planes (software decoder) -> replaceRegion into a ring of upload textures

#import <CoreVideo/CoreVideo.h>
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <Syphon/SyphonMetalServer.h>

#include <math.h>
#include <stdarg.h>
#include <stdio.h>

#include "publisher.h"

#if !__has_feature(objc_arc)
#error "publisher.m must be compiled with -fobjc-arc"
#endif

// Frames that may be in flight on the GPU at once. Also the number of CPU upload slots.
#define VSN_INFLIGHT 3

static void set_err(char *err, size_t size, const char *fmt, ...)
{
    if (!err || !size)
        return;
    va_list ap;
    va_start(ap, fmt);
    vsnprintf(err, size, fmt, ap);
    va_end(ap);
}

#pragma mark - Shaders

// shaders.metal, embedded by CMake as `static const char vsn_shader_source[]`.
#include "shaders_metal.h"

typedef struct VSNParams {
    float crop[4];
    float r[4], g[4], b[4];
} VSNParams;

// Fills the YCbCr -> RGB rows of p for sampled values normalized to 0..1.
static void yuv_matrix(VSNParams *p, vsn_colorspace cs, bool full_range)
{
    float kr, kb;
    switch (cs) {
    case VSN_COLORSPACE_BT709:  kr = 0.2126f; kb = 0.0722f; break;
    case VSN_COLORSPACE_BT2020: kr = 0.2627f; kb = 0.0593f; break;
    case VSN_COLORSPACE_BT601:
    default:                    kr = 0.299f;  kb = 0.114f;  break;
    }
    const float kg = 1.0f - kr - kb;

    // Y' = ys * (Y - yo), Cb' = cs * (Cb - 0.5), Cr' = cs * (Cr - 0.5)
    const float yo = full_range ? 0.0f : 16.0f / 255.0f;
    const float ys = full_range ? 1.0f : 255.0f / 219.0f;
    const float cc = full_range ? 1.0f : 255.0f / 224.0f;

    const float r_cr = 2.0f - 2.0f * kr;
    const float b_cb = 2.0f - 2.0f * kb;
    const float g_cb = -b_cb * kb / kg;
    const float g_cr = -r_cr * kr / kg;

    const float rows[3][3] = {
        { ys, 0.0f,        cc * r_cr },
        { ys, cc * g_cb,   cc * g_cr },
        { ys, cc * b_cb,   0.0f      },
    };
    float *out[3] = { p->r, p->g, p->b };
    for (int i = 0; i < 3; i++) {
        out[i][0] = rows[i][0];
        out[i][1] = rows[i][1];
        out[i][2] = rows[i][2];
        out[i][3] = -(rows[i][0] * yo + (rows[i][1] + rows[i][2]) * 0.5f);
    }
}

#pragma mark - Plane layout

typedef enum { VSN_SHADER_BIPLANAR, VSN_SHADER_PLANAR, VSN_SHADER_RGB } VSNShader;

typedef struct VSNLayout {
    VSNShader shader;
    int planes;
    MTLPixelFormat format[3];
    unsigned wdiv[3], hdiv[3];  // plane size = ceil(size / div)
    unsigned bpp[3];            // bytes per pixel in each plane
} VSNLayout;

static bool layout_for(vsn_pixfmt fmt, VSNLayout *l)
{
    switch (fmt) {
    case VSN_PIXFMT_NV12:
        *l = (VSNLayout){ VSN_SHADER_BIPLANAR, 2, { MTLPixelFormatR8Unorm, MTLPixelFormatRG8Unorm },
                          { 1, 2 }, { 1, 2 }, { 1, 2 } };
        return true;
    case VSN_PIXFMT_P010:
        *l = (VSNLayout){ VSN_SHADER_BIPLANAR, 2, { MTLPixelFormatR16Unorm, MTLPixelFormatRG16Unorm },
                          { 1, 2 }, { 1, 2 }, { 2, 4 } };
        return true;
    case VSN_PIXFMT_I420:
        *l = (VSNLayout){ VSN_SHADER_PLANAR, 3,
                          { MTLPixelFormatR8Unorm, MTLPixelFormatR8Unorm, MTLPixelFormatR8Unorm },
                          { 1, 2, 2 }, { 1, 2, 2 }, { 1, 1, 1 } };
        return true;
    case VSN_PIXFMT_BGRA:
        *l = (VSNLayout){ VSN_SHADER_RGB, 1, { MTLPixelFormatBGRA8Unorm }, { 1 }, { 1 }, { 4 } };
        return true;
    case VSN_PIXFMT_RGBA:
        *l = (VSNLayout){ VSN_SHADER_RGB, 1, { MTLPixelFormatRGBA8Unorm }, { 1 }, { 1 }, { 4 } };
        return true;
    default:
        return false;
    }
}

bool vsn_syphon_supports(vsn_pixfmt pixfmt, vsn_memory memory)
{
    VSNLayout l;
    if (!layout_for(pixfmt, &l))
        return false;
    return memory == VSN_MEMORY_CPU || memory == VSN_MEMORY_CVPIXELBUFFER;
}

#pragma mark - Publisher

@interface VSNSyphonPublisher : NSObject
@end

@implementation VSNSyphonPublisher {
@public
    id<MTLDevice> _device;
    id<MTLCommandQueue> _queue;
    SyphonMetalServer *_server;
    id<MTLRenderPipelineState> _pipelines[3];
    CVMetalTextureCacheRef _textureCache;
    id<MTLTexture> _output;
    dispatch_semaphore_t _inflight;
    id<MTLCommandBuffer> _lastCommandBuffer;
    bool _squarePixels;

    NSLock *_lock;             // serialises the C API (several VLC threads use one server)
    uint64_t _generation;      // bumped by every publish; a pending clear checks it
    unsigned _lastW, _lastH;   // size of the last published frame
    dispatch_queue_t _timers;

    // CPU upload ring
    NSArray<id<MTLTexture>> *_upload[VSN_INFLIGHT];
    unsigned _uploadSlot;
}

- (instancetype)initWithConfig:(const vsn_syphon_config *)cfg error:(NSString **)error
{
    if (!(self = [super init]))
        return nil;

    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        *error = @"no Metal device";
        return nil;
    }
    _queue = [_device newCommandQueue];
    _inflight = dispatch_semaphore_create(VSN_INFLIGHT);
    _lock = [NSLock new];
    _lastW = 1920;
    _lastH = 1080;
    _timers = dispatch_queue_create("vsn.syphon.timers", DISPATCH_QUEUE_SERIAL);

    NSError *err = nil;
    id<MTLLibrary> lib = [_device newLibraryWithSource:@(vsn_shader_source) options:nil error:&err];
    if (!lib) {
        *error = [NSString stringWithFormat:@"shader compilation failed: %@", err];
        return nil;
    }
    NSString *fragments[3] = { @"vsn_biplanar", @"vsn_planar", @"vsn_rgb" };
    for (int i = 0; i < 3; i++) {
        MTLRenderPipelineDescriptor *d = [MTLRenderPipelineDescriptor new];
        d.vertexFunction = [lib newFunctionWithName:@"vsn_vertex"];
        d.fragmentFunction = [lib newFunctionWithName:fragments[i]];
        d.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
        _pipelines[i] = [_device newRenderPipelineStateWithDescriptor:d error:&err];
        if (!_pipelines[i]) {
            *error = [NSString stringWithFormat:@"pipeline creation failed: %@", err];
            return nil;
        }
    }

    if (CVMetalTextureCacheCreate(kCFAllocatorDefault, NULL, _device, NULL, &_textureCache)
        != kCVReturnSuccess) {
        *error = @"CVMetalTextureCacheCreate failed";
        return nil;
    }

    NSString *name = (cfg->name && *cfg->name) ? [NSString stringWithUTF8String:cfg->name] : nil;
    _server = [[SyphonMetalServer alloc] initWithName:name device:_device options:nil];
    if (!_server) {
        *error = @"could not start the Syphon server";
        return nil;
    }
    return self;
}

- (void)dealloc
{
    [_lastCommandBuffer waitUntilCompleted];
    [_server stop];
    if (_textureCache)
        CFRelease(_textureCache);
}

- (id<MTLTexture>)outputWithWidth:(unsigned)w height:(unsigned)h
{
    if (_output.width != w || _output.height != h) {
        MTLTextureDescriptor *d =
            [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                               width:w height:h mipmapped:NO];
        d.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
        d.storageMode = MTLStorageModePrivate;
        _output = [_device newTextureWithDescriptor:d];
    }
    return _output;
}

// Copies the CPU planes into the next upload slot. Called after waiting on _inflight,
// so the slot's textures are no longer read by the GPU.
- (NSArray<id<MTLTexture>> *)uploadFrame:(const vsn_frame *)f layout:(const VSNLayout *)l
{
    NSArray<id<MTLTexture>> *slot = _upload[_uploadSlot];
    bool reuse = slot.count == (NSUInteger)l->planes;
    for (int i = 0; reuse && i < l->planes; i++) {
        id<MTLTexture> t = slot[i];
        reuse = t.pixelFormat == l->format[i]
             && t.width == (f->width + l->wdiv[i] - 1) / l->wdiv[i]
             && t.height == (f->height + l->hdiv[i] - 1) / l->hdiv[i];
    }
    if (!reuse) {
        NSMutableArray *textures = [NSMutableArray arrayWithCapacity:l->planes];
        for (int i = 0; i < l->planes; i++) {
            MTLTextureDescriptor *d = [MTLTextureDescriptor
                texture2DDescriptorWithPixelFormat:l->format[i]
                                             width:(f->width + l->wdiv[i] - 1) / l->wdiv[i]
                                            height:(f->height + l->hdiv[i] - 1) / l->hdiv[i]
                                         mipmapped:NO];
            d.usage = MTLTextureUsageShaderRead;
            d.storageMode = _device.hasUnifiedMemory ? MTLStorageModeShared : MTLStorageModeManaged;
            id<MTLTexture> t = [_device newTextureWithDescriptor:d];
            if (!t)
                return nil;
            [textures addObject:t];
        }
        slot = textures;
        _upload[_uploadSlot] = slot;
    }
    for (int i = 0; i < l->planes; i++) {
        id<MTLTexture> t = slot[i];
        if (f->planes[i].stride < (int)(t.width * l->bpp[i]) || f->planes[i].lines < (int)t.height)
            return nil;
        [t replaceRegion:MTLRegionMake2D(0, 0, t.width, t.height)
             mipmapLevel:0
               withBytes:f->planes[i].data
             bytesPerRow:f->planes[i].stride];
    }
    _uploadSlot = (_uploadSlot + 1) % VSN_INFLIGHT;
    return slot;
}

static bool cvpx_layout(OSType type, vsn_pixfmt *fmt, bool *full_range)
{
    switch (type) {
    case kCVPixelFormatType_420YpCbCr8BiPlanarVideoRange:  *fmt = VSN_PIXFMT_NV12; *full_range = false; return true;
    case kCVPixelFormatType_420YpCbCr8BiPlanarFullRange:   *fmt = VSN_PIXFMT_NV12; *full_range = true;  return true;
    case kCVPixelFormatType_420YpCbCr10BiPlanarVideoRange: *fmt = VSN_PIXFMT_P010; *full_range = false; return true;
    case kCVPixelFormatType_420YpCbCr10BiPlanarFullRange:  *fmt = VSN_PIXFMT_P010; *full_range = true;  return true;
    case kCVPixelFormatType_420YpCbCr8Planar:              *fmt = VSN_PIXFMT_I420; *full_range = false; return true;
    case kCVPixelFormatType_420YpCbCr8PlanarFullRange:     *fmt = VSN_PIXFMT_I420; *full_range = true;  return true;
    case kCVPixelFormatType_32BGRA:                        *fmt = VSN_PIXFMT_BGRA; *full_range = true;  return true;
    default: return false;
    }
}

// Software fallback for CVPixelBuffers that Metal can't wrap (not IOSurface-backed):
// map them and upload like a CPU frame.
- (BOOL)publishMappedPixelBuffer:(CVPixelBufferRef)pb frame:(const vsn_frame *)frame
                          error:(NSString **)error
{
    VSNLayout layout;
    if (!layout_for(frame->pixfmt, &layout)) {
        *error = @"unsupported CVPixelBuffer format";
        return NO;
    }
    if (CVPixelBufferLockBaseAddress(pb, kCVPixelBufferLock_ReadOnly) != kCVReturnSuccess) {
        *error = @"could not map the CVPixelBuffer";
        return NO;
    }
    vsn_frame cpu = *frame;
    cpu.memory = VSN_MEMORY_CPU;
    cpu.native = NULL;
    size_t planes = CVPixelBufferGetPlaneCount(pb);
    cpu.plane_count = planes ? (int)planes : 1;
    for (int i = 0; i < cpu.plane_count && i < VSN_MAX_PLANES; i++) {
        uint8_t *base = planes ? CVPixelBufferGetBaseAddressOfPlane(pb, i) : CVPixelBufferGetBaseAddress(pb);
        size_t stride = planes ? CVPixelBufferGetBytesPerRowOfPlane(pb, i) : CVPixelBufferGetBytesPerRow(pb);
        size_t rows = planes ? CVPixelBufferGetHeightOfPlane(pb, i) : CVPixelBufferGetHeight(pb);
        size_t width = planes ? CVPixelBufferGetWidthOfPlane(pb, i) : CVPixelBufferGetWidth(pb);
        size_t full_w = CVPixelBufferGetWidth(pb), full_h = CVPixelBufferGetHeight(pb);
        size_t x = frame->x_offset * width / full_w, y = frame->y_offset * rows / full_h;
        size_t bpp = layout.bpp[i];
        cpu.planes[i].data = base + y * stride + x * bpp;
        cpu.planes[i].stride = (int)stride;
        cpu.planes[i].lines = (int)(rows - y);
    }
    cpu.x_offset = cpu.y_offset = 0;
    BOOL ok = [self publish:&cpu error:error];
    // replaceRegion copied the pixels synchronously, so the buffer can be unmapped now.
    CVPixelBufferUnlockBaseAddress(pb, kCVPixelBufferLock_ReadOnly);
    return ok;
}

- (void)publishColorWidth:(unsigned)w height:(unsigned)h rgba:(const float *)c
{
    _generation++;
    if (!w || !h) {
        w = _lastW;
        h = _lastH;
    }
    dispatch_semaphore_wait(_inflight, DISPATCH_TIME_FOREVER);
    id<MTLTexture> output = [self outputWithWidth:w height:h];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = output;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(c[0], c[1], c[2], c[3]);
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    [[cb renderCommandEncoderWithDescriptor:pass] endEncoding];
    [_server publishFrameTexture:output onCommandBuffer:cb
                     imageRegion:NSMakeRect(0, 0, w, h) flipped:YES];
    dispatch_semaphore_t inflight = _inflight;
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done) { dispatch_semaphore_signal(inflight); }];
    [cb commit];
    _lastCommandBuffer = cb;
    _lastW = w;
    _lastH = h;
}

- (BOOL)publish:(const vsn_frame *)frame error:(NSString **)error
{
    _generation++;
    vsn_frame f = *frame;
    unsigned srcW = f.width, srcH = f.height;  // full source texture size, for the crop
    CVPixelBufferRef pb = NULL;

    if (f.memory == VSN_MEMORY_CVPIXELBUFFER) {
        pb = (CVPixelBufferRef)f.native;
        if (!pb || !cvpx_layout(CVPixelBufferGetPixelFormatType(pb), &f.pixfmt, &f.full_range)) {
            *error = @"unsupported CVPixelBuffer format";
            return NO;
        }
        if (!CVPixelBufferGetIOSurface(pb))
            return [self publishMappedPixelBuffer:pb frame:&f error:error];
        srcW = (unsigned)CVPixelBufferGetWidth(pb);
        srcH = (unsigned)CVPixelBufferGetHeight(pb);
    } else if (f.memory != VSN_MEMORY_CPU) {
        *error = @"unsupported frame memory";
        return NO;
    }

    VSNLayout layout;
    if (!layout_for(f.pixfmt, &layout) || f.width == 0 || f.height == 0) {
        *error = [NSString stringWithFormat:@"unsupported frame %s %ux%u",
                  vsn_pixfmt_name(f.pixfmt), f.width, f.height];
        return NO;
    }

    unsigned outW = f.width, outH = f.height;
    if (_squarePixels && f.sar_num && f.sar_den && f.sar_num != f.sar_den)
        outW = (unsigned)lround((double)f.width * f.sar_num / f.sar_den);

    dispatch_semaphore_wait(_inflight, DISPATCH_TIME_FOREVER);

    NSMutableArray *textures = [NSMutableArray arrayWithCapacity:3];
    CVMetalTextureRef cvTextures[3] = { NULL, NULL, NULL };
    BOOL ok = YES;
    if (pb) {
        for (int i = 0; i < layout.planes; i++) {
            size_t w = CVPixelBufferGetPlaneCount(pb) ? CVPixelBufferGetWidthOfPlane(pb, i) : srcW;
            size_t h = CVPixelBufferGetPlaneCount(pb) ? CVPixelBufferGetHeightOfPlane(pb, i) : srcH;
            if (CVMetalTextureCacheCreateTextureFromImage(kCFAllocatorDefault, _textureCache, pb, NULL,
                                                          layout.format[i], w, h, i, &cvTextures[i])
                    != kCVReturnSuccess
                || !CVMetalTextureGetTexture(cvTextures[i])) {
                ok = NO;
                break;
            }
            [textures addObject:CVMetalTextureGetTexture(cvTextures[i])];
        }
        if (ok)
            CVPixelBufferRetain(pb);
    } else {
        NSArray *uploaded = [self uploadFrame:&f layout:&layout];
        if (uploaded)
            [textures addObjectsFromArray:uploaded];
        else
            ok = NO;
    }
    if (!ok) {
        for (int i = 0; i < 3; i++)
            if (cvTextures[i])
                CFRelease(cvTextures[i]);
        dispatch_semaphore_signal(_inflight);
        *error = pb ? @"could not wrap the CVPixelBuffer in Metal textures"
                    : @"could not upload the frame";
        return NO;
    }

    VSNParams params = {
        .crop = { (float)f.x_offset / srcW, (float)f.y_offset / srcH,
                  (float)f.width / srcW, (float)f.height / srcH },
    };
    yuv_matrix(&params, f.colorspace, f.full_range);

    id<MTLTexture> output = [self outputWithWidth:outW height:outH];
    MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = output;
    pass.colorAttachments[0].loadAction = MTLLoadActionDontCare;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;

    id<MTLCommandBuffer> cb = [_queue commandBuffer];
    id<MTLRenderCommandEncoder> enc = [cb renderCommandEncoderWithDescriptor:pass];
    [enc setRenderPipelineState:_pipelines[layout.shader]];
    [enc setVertexBytes:&params length:sizeof(params) atIndex:0];
    [enc setFragmentBytes:&params length:sizeof(params) atIndex:0];
    for (NSUInteger i = 0; i < textures.count; i++)
        [enc setFragmentTexture:textures[i] atIndex:i];
    [enc drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [enc endEncoding];

    [_server publishFrameTexture:output onCommandBuffer:cb
                     imageRegion:NSMakeRect(0, 0, outW, outH) flipped:YES];

    dispatch_semaphore_t inflight = _inflight;
    CVMetalTextureRef t0 = cvTextures[0], t1 = cvTextures[1], t2 = cvTextures[2];
    [cb addCompletedHandler:^(id<MTLCommandBuffer> done) {
        if (t0) CFRelease(t0);
        if (t1) CFRelease(t1);
        if (t2) CFRelease(t2);
        if (pb) CVPixelBufferRelease(pb);
        dispatch_semaphore_signal(inflight);
    }];
    [cb commit];
    _lastCommandBuffer = cb;
    _lastW = outW;
    _lastH = outH;
    // Let the cache drop textures for pixel buffers VLC has recycled.
    if (pb)
        CVMetalTextureCacheFlush(_textureCache, 0);
    return YES;
}

@end

#pragma mark - C API

struct vsn_syphon {
    void *publisher;  // VSNSyphonPublisher, retained
};

vsn_syphon *vsn_syphon_create(const vsn_syphon_config *cfg, char *err, size_t err_size)
{
    @autoreleasepool {
        NSString *error = nil;
        VSNSyphonPublisher *p = [[VSNSyphonPublisher alloc] initWithConfig:cfg error:&error];
        if (!p) {
            set_err(err, err_size, "%s", error.UTF8String ?: "unknown error");
            return NULL;
        }
        vsn_syphon *s = calloc(1, sizeof(*s));
        if (!s) {
            set_err(err, err_size, "out of memory");
            return NULL;
        }
        s->publisher = (__bridge_retained void *)p;
        return s;
    }
}

bool vsn_syphon_has_clients(vsn_syphon *s)
{
    VSNSyphonPublisher *p = (__bridge VSNSyphonPublisher *)s->publisher;
    return p->_server.hasClients;
}

bool vsn_syphon_publish(vsn_syphon *s, const vsn_frame *frame, bool square_pixels,
                        char *err, size_t err_size)
{
    @autoreleasepool {
        VSNSyphonPublisher *p = (__bridge VSNSyphonPublisher *)s->publisher;
        NSString *error = nil;
        [p->_lock lock];
        p->_squarePixels = square_pixels;
        BOOL ok = [p publish:frame error:&error];
        [p->_lock unlock];
        if (ok)
            return true;
        set_err(err, err_size, "%s", error.UTF8String ?: "unknown error");
        return false;
    }
}

void vsn_syphon_publish_color(vsn_syphon *s, unsigned width, unsigned height,
                              float r, float g, float b, float a)
{
    @autoreleasepool {
        VSNSyphonPublisher *p = (__bridge VSNSyphonPublisher *)s->publisher;
        const float c[4] = { r, g, b, a };
        [p->_lock lock];
        [p publishColorWidth:width height:height rgba:c];
        [p->_lock unlock];
    }
}

void vsn_syphon_clear_later(vsn_syphon *s, unsigned delay_ms, float r, float g, float b, float a)
{
    VSNSyphonPublisher *p = (__bridge VSNSyphonPublisher *)s->publisher;
    [p->_lock lock];
    uint64_t generation = ++p->_generation;
    [p->_lock unlock];

    __weak VSNSyphonPublisher *weak = p;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)delay_ms * NSEC_PER_MSEC), p->_timers, ^{
        VSNSyphonPublisher *strong = weak;  // nil once the server is destroyed
        if (!strong)
            return;
        @autoreleasepool {
            const float c[4] = { r, g, b, a };
            [strong->_lock lock];
            if (strong->_generation == generation)  // nothing published since
                [strong publishColorWidth:0 height:0 rgba:c];
            [strong->_lock unlock];
        }
    });
}

void vsn_syphon_set_name(vsn_syphon *s, const char *name)
{
    @autoreleasepool {
        VSNSyphonPublisher *p = (__bridge VSNSyphonPublisher *)s->publisher;
        [p->_lock lock];
        p->_server.name = (name && *name) ? @(name) : nil;
        [p->_lock unlock];
    }
}

void vsn_syphon_destroy(vsn_syphon *s)
{
    if (!s)
        return;
    @autoreleasepool {
        // Dropping the last reference runs dealloc: waits for the GPU, stops the server.
        CFBridgingRelease(s->publisher);
    }
    free(s);
}
