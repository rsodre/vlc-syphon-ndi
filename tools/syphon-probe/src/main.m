// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// syphon-probe: minimal Syphon client for testing the syphon plugin.
// Lists servers, connects to the first one matching --server/--app, waits for a
// frame, prints its size and a few pixel values, and optionally saves it as PNG.
//
// Frames are read with an OpenGL client by default, as most Syphon clients (Simple
// Client, Resolume, MadMapper, ...) do, and reported as they display them: pixel 0,0 is
// the top-left of the picture. --metal reads with SyphonMetalClient instead, as raw
// texture rows (row 0 first).
//
//   syphon-probe --list
//   syphon-probe --app VLC --out frame.png [--timeout 10] [--pixel x,y]...

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <Metal/Metal.h>
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#import <OpenGL/glext.h>
#import <Syphon/Syphon.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

static void usage(void)
{
    fprintf(stderr, "usage: syphon-probe [--list] [--server NAME] [--app NAME] [--out FILE.png]\n"
                    "                    [--timeout SECONDS] [--pixel X,Y]...\n");
    exit(2);
}

static NSArray *wait_for_servers(NSString *server, NSString *app, double timeout)
{
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    NSArray *found = nil;
    do {
        // The directory is filled from distributed notifications, delivered on this run loop.
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        found = [[SyphonServerDirectory sharedDirectory] serversMatchingName:server appName:app];
    } while (found.count == 0 && deadline.timeIntervalSinceNow > 0);
    return found;
}

int main(int argc, const char **argv)
{
    @autoreleasepool {
        NSString *server = nil, *app = nil, *out = nil;
        double timeout = 10;
        bool list = false, use_metal = false;
        NSMutableArray<NSValue *> *pixels = [NSMutableArray array];

        for (int i = 1; i < argc; i++) {
            NSString *a = @(argv[i]);
            if ([a isEqual:@"--list"]) list = true;
            else if ([a isEqual:@"--metal"]) use_metal = true;
            else if (i + 1 >= argc) usage();
            else if ([a isEqual:@"--server"]) server = @(argv[++i]);
            else if ([a isEqual:@"--app"]) app = @(argv[++i]);
            else if ([a isEqual:@"--out"]) out = @(argv[++i]);
            else if ([a isEqual:@"--timeout"]) timeout = atof(argv[++i]);
            else if ([a isEqual:@"--pixel"]) {
                int x, y;
                if (sscanf(argv[++i], "%d,%d", &x, &y) != 2) usage();
                [pixels addObject:[NSValue valueWithPoint:NSMakePoint(x, y)]];
            } else usage();
        }

        NSArray *servers = wait_for_servers(server, app, list ? MIN(timeout, 2) : timeout);
        for (NSDictionary *d in servers)
            printf("server: app=\"%s\" name=\"%s\"\n", [d[SyphonServerDescriptionAppNameKey] UTF8String],
                   [d[SyphonServerDescriptionNameKey] UTF8String]);
        if (list)
            return 0;
        if (servers.count == 0) {
            fprintf(stderr, "no matching Syphon server\n");
            return 1;
        }

        NSUInteger w = 0, h = 0;
        NSMutableData *bgra = nil;  // top row first
        dispatch_semaphore_t got = dispatch_semaphore_create(0);
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        BOOL (^waitFrame)(void) = ^BOOL {
            while (dispatch_semaphore_wait(got, DISPATCH_TIME_NOW) != 0) {
                if (deadline.timeIntervalSinceNow < 0) {
                    fprintf(stderr, "no frame received within %.0f s\n", timeout);
                    return NO;
                }
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            }
            return YES;
        };

        if (use_metal) {
            id<MTLDevice> device = MTLCreateSystemDefaultDevice();
            SyphonMetalClient *client =
                [[SyphonMetalClient alloc] initWithServerDescription:servers.firstObject device:device options:nil
                                                     newFrameHandler:^(SyphonMetalClient *c) { dispatch_semaphore_signal(got); }];
            if (!waitFrame())
                return 1;
            id<MTLTexture> frame = [client newFrameImage];
            if (!frame) {
                fprintf(stderr, "client returned no texture\n");
                return 1;
            }
            w = frame.width;
            h = frame.height;
            printf("frame: %lux%lu pixelFormat=%lu (metal, raw rows)\n", (unsigned long)w, (unsigned long)h,
                   (unsigned long)frame.pixelFormat);
            MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:frame.pixelFormat
                                                                                         width:w height:h mipmapped:NO];
            d.storageMode = device.hasUnifiedMemory ? MTLStorageModeShared : MTLStorageModeManaged;
            id<MTLTexture> readable = [device newTextureWithDescriptor:d];
            id<MTLCommandBuffer> cb = [[device newCommandQueue] commandBuffer];
            id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
            [blit copyFromTexture:frame toTexture:readable];
            if (!device.hasUnifiedMemory)
                [blit synchronizeResource:readable];
            [blit endEncoding];
            [cb commit];
            [cb waitUntilCompleted];
            bgra = [NSMutableData dataWithLength:w * h * 4];
            [readable getBytes:bgra.mutableBytes bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h) mipmapLevel:0];
            [client stop];
        } else {
            CGLPixelFormatAttribute attrs[] = { kCGLPFAAccelerated, kCGLPFAAllowOfflineRenderers, 0 };
            CGLPixelFormatObj pf = NULL;
            GLint npix = 0;
            CGLContextObj ctx = NULL;
            if (CGLChoosePixelFormat(attrs, &pf, &npix) != kCGLNoError || !pf
                || CGLCreateContext(pf, NULL, &ctx) != kCGLNoError) {
                fprintf(stderr, "cannot create an OpenGL context\n");
                return 1;
            }
            CGLSetCurrentContext(ctx);
            SyphonOpenGLClient *client =
                [[SyphonOpenGLClient alloc] initWithServerDescription:servers.firstObject context:ctx options:nil
                                                      newFrameHandler:^(SyphonOpenGLClient *c) { dispatch_semaphore_signal(got); }];
            if (!waitFrame())
                return 1;
            SyphonOpenGLImage *image = [client newFrameImage];
            if (!image) {
                fprintf(stderr, "client returned no image\n");
                return 1;
            }
            w = (NSUInteger)image.textureSize.width;
            h = (NSUInteger)image.textureSize.height;
            printf("frame: %lux%lu (opengl, as displayed)\n", (unsigned long)w, (unsigned long)h);
            // Draw the texture like a client does (texture coordinate 0,0 at the bottom-left of
            // the screen) into an offscreen framebuffer, then read it back. glGetTexImage
            // can't read IOSurface-backed textures.
            GLuint fbo = 0, rb = 0;
            glGenFramebuffersEXT(1, &fbo);
            glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, fbo);
            glGenRenderbuffersEXT(1, &rb);
            glBindRenderbufferEXT(GL_RENDERBUFFER_EXT, rb);
            glRenderbufferStorageEXT(GL_RENDERBUFFER_EXT, GL_RGBA8, (GLsizei)w, (GLsizei)h);
            glFramebufferRenderbufferEXT(GL_FRAMEBUFFER_EXT, GL_COLOR_ATTACHMENT0_EXT, GL_RENDERBUFFER_EXT, rb);
            glViewport(0, 0, (GLsizei)w, (GLsizei)h);
            glMatrixMode(GL_PROJECTION);
            glLoadIdentity();
            glMatrixMode(GL_MODELVIEW);
            glLoadIdentity();
            glClearColor(0, 0, 0, 0);
            glClear(GL_COLOR_BUFFER_BIT);
            glEnable(GL_TEXTURE_RECTANGLE_ARB);
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, image.textureName);
            glTexEnvi(GL_TEXTURE_ENV, GL_TEXTURE_ENV_MODE, GL_REPLACE);
            glBegin(GL_QUADS);
            glTexCoord2f(0, 0);                   glVertex2f(-1, -1);
            glTexCoord2f((GLfloat)w, 0);          glVertex2f(1, -1);
            glTexCoord2f((GLfloat)w, (GLfloat)h); glVertex2f(1, 1);
            glTexCoord2f(0, (GLfloat)h);          glVertex2f(-1, 1);
            glEnd();
            glFinish();
            NSMutableData *gl = [NSMutableData dataWithLength:w * h * 4];
            glReadPixels(0, 0, (GLsizei)w, (GLsizei)h, GL_BGRA, GL_UNSIGNED_INT_8_8_8_8_REV, gl.mutableBytes);
            glBindTexture(GL_TEXTURE_RECTANGLE_ARB, 0);
            glBindFramebufferEXT(GL_FRAMEBUFFER_EXT, 0);
            glDeleteRenderbuffersEXT(1, &rb);
            glDeleteFramebuffersEXT(1, &fbo);
            // OpenGL row 0 is the bottom of the picture: store top row first.
            bgra = [NSMutableData dataWithLength:w * h * 4];
            for (NSUInteger y = 0; y < h; y++)
                memcpy((uint8_t *)bgra.mutableBytes + y * w * 4, (const uint8_t *)gl.bytes + (h - 1 - y) * w * 4, w * 4);
            [client stop];
            CGLSetCurrentContext(NULL);
            CGLDestroyContext(ctx);
            CGLReleasePixelFormat(pf);
        }
        const uint8_t *px = bgra.bytes;

        if (pixels.count == 0)
            [pixels addObject:[NSValue valueWithPoint:NSMakePoint(w / 2, h / 2)]];
        for (NSValue *v in pixels) {
            NSUInteger x = MIN((NSUInteger)v.pointValue.x, w - 1), y = MIN((NSUInteger)v.pointValue.y, h - 1);
            const uint8_t *p = px + (y * w + x) * 4;
            printf("pixel %lu,%lu: r=%u g=%u b=%u a=%u\n", (unsigned long)x, (unsigned long)y,
                   p[2], p[1], p[0], p[3]);
        }

        if (out) {
            CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
            CGDataProviderRef dp = CGDataProviderCreateWithCFData((__bridge CFDataRef)bgra);
            CGImageRef img = CGImageCreate(w, h, 8, 32, w * 4, cs,
                                           kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
                                           dp, NULL, false, kCGRenderingIntentDefault);
            CGImageDestinationRef dst = CGImageDestinationCreateWithURL(
                (__bridge CFURLRef)[NSURL fileURLWithPath:out], (__bridge CFStringRef)UTTypePNG.identifier, 1, NULL);
            CGImageDestinationAddImage(dst, img, NULL);
            bool ok = CGImageDestinationFinalize(dst);
            CFRelease(dst); CGImageRelease(img); CGDataProviderRelease(dp); CGColorSpaceRelease(cs);
            if (!ok) {
                fprintf(stderr, "could not write %s\n", out.UTF8String);
                return 1;
            }
            printf("saved: %s\n", out.UTF8String);
        }
    }
    return 0;
}
