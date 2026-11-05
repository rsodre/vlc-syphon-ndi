// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// syphon-probe: minimal Syphon client for testing the syphon plugin.
// Lists servers, connects to the first one matching --server/--app, waits for a
// frame, prints its size and a few pixel values, and optionally saves it as PNG.
//
//   syphon-probe --list
//   syphon-probe --app VLC --out frame.png [--timeout 10] [--pixel x,y]...

#import <CoreGraphics/CoreGraphics.h>
#import <Foundation/Foundation.h>
#import <ImageIO/ImageIO.h>
#import <Metal/Metal.h>
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
        bool list = false;
        NSMutableArray<NSValue *> *pixels = [NSMutableArray array];

        for (int i = 1; i < argc; i++) {
            NSString *a = @(argv[i]);
            if ([a isEqual:@"--list"]) list = true;
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

        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        dispatch_semaphore_t got = dispatch_semaphore_create(0);
        SyphonMetalClient *client =
            [[SyphonMetalClient alloc] initWithServerDescription:servers.firstObject device:device
                                                         options:nil
                                                 newFrameHandler:^(SyphonMetalClient *c) {
                                                     dispatch_semaphore_signal(got);
                                                 }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
        while (dispatch_semaphore_wait(got, DISPATCH_TIME_NOW) != 0) {
            if (deadline.timeIntervalSinceNow < 0) {
                fprintf(stderr, "no frame received within %.0f s\n", timeout);
                return 1;
            }
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }

        id<MTLTexture> frame = [client newFrameImage];
        if (!frame) {
            fprintf(stderr, "client returned no texture\n");
            return 1;
        }
        NSUInteger w = frame.width, h = frame.height;
        printf("frame: %lux%lu pixelFormat=%lu\n", (unsigned long)w, (unsigned long)h,
               (unsigned long)frame.pixelFormat);

        // Copy to a CPU-readable texture.
        MTLTextureDescriptor *d = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:frame.pixelFormat
                                                                                     width:w height:h
                                                                                 mipmapped:NO];
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

        NSMutableData *bgra = [NSMutableData dataWithLength:w * h * 4];
        [readable getBytes:bgra.mutableBytes bytesPerRow:w * 4 fromRegion:MTLRegionMake2D(0, 0, w, h)
               mipmapLevel:0];
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
        [client stop];
    }
    return 0;
}
