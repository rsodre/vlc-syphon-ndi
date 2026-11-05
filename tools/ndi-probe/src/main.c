// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// ndi-probe: minimal NDI receiver for testing the ndi plugin.
//
//   ndi-probe --list
//   ndi-probe --source NAME [--timeout S] [--pixel X,Y]... [--seconds S]
//
// Connects to the first source whose name contains NAME, prints the first video
// frame's format and pixel values (as BGRA), and audio format and level.
// With --seconds, it keeps receiving and measures A/V sync on a clip that flashes
// white and beeps at the same time: for each flash it reports the offset to the
// nearest beep onset, using the sender's timestamps.

#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#ifdef _WIN32
# include <windows.h>
#endif

#include <vsn/ndi_runtime.h>

#define MAX_EVENTS 256
#define MAX_PIXELS 16

static double now_s(void)
{
#ifdef _WIN32
    LARGE_INTEGER f, c;
    QueryPerformanceFrequency(&f);
    QueryPerformanceCounter(&c);
    return (double)c.QuadPart / f.QuadPart;
#else
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return ts.tv_sec + ts.tv_nsec / 1e9;
#endif
}

static void usage(void)
{
    fprintf(stderr, "usage: ndi-probe [--list] [--source NAME] [--timeout S] [--pixel X,Y]... [--seconds S]\n");
    exit(2);
}

int main(int argc, char **argv)
{
    const char *want = NULL;
    double timeout = 10, seconds = 0;
    int list = 0, npx = 0, px[MAX_PIXELS][2];

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--list")) list = 1;
        else if (i + 1 >= argc) usage();
        else if (!strcmp(argv[i], "--source")) want = argv[++i];
        else if (!strcmp(argv[i], "--timeout")) timeout = atof(argv[++i]);
        else if (!strcmp(argv[i], "--seconds")) seconds = atof(argv[++i]);
        else if (!strcmp(argv[i], "--pixel") && npx < MAX_PIXELS) {
            if (sscanf(argv[++i], "%d,%d", &px[npx][0], &px[npx][1]) != 2) usage();
            npx++;
        } else usage();
    }

    char err[2048];
    const NDIlib_v6 *ndi = vsn_ndi_load(err, sizeof(err));
    if (!ndi) {
        fprintf(stderr, "%s\n", err);
        return 1;
    }
    printf("runtime: %s (%s)\n", vsn_ndi_runtime_path(), ndi->version());

    NDIlib_find_create_t fc = { .show_local_sources = true, .p_groups = NULL, .p_extra_ips = NULL };
    NDIlib_find_instance_t find = ndi->find_create_v2(&fc);
    const NDIlib_source_t *match = NULL;
    double deadline = now_s() + (list ? fmin(timeout, 3) : timeout);
    while (now_s() < deadline && !match) {
        ndi->find_wait_for_sources(find, 500);
        uint32_t n = 0;
        const NDIlib_source_t *sources = ndi->find_get_current_sources(find, &n);
        for (uint32_t i = 0; i < n && !list; i++)
            if (!want || strstr(sources[i].p_ndi_name, want))
                match = &sources[i];
        if (list && now_s() + 0.5 >= deadline)
            for (uint32_t i = 0; i < n; i++)
                printf("source: %s\n", sources[i].p_ndi_name);
    }
    if (list)
        return 0;
    if (!match) {
        fprintf(stderr, "no matching NDI source\n");
        return 1;
    }
    printf("source: %s\n", match->p_ndi_name);

    NDIlib_recv_create_v3_t rc = {
        .source_to_connect_to = *match,
        .color_format = NDIlib_recv_color_format_BGRX_BGRA,
        .bandwidth = NDIlib_recv_bandwidth_highest,
        .allow_video_fields = false,
        .p_ndi_recv_name = "ndi-probe",
    };
    NDIlib_recv_instance_t recv = ndi->recv_create_v3(&rc);
    if (!recv) {
        fprintf(stderr, "cannot create receiver\n");
        return 1;
    }

    int got_video = 0, video_frames = 0, audio_frames = 0;
    int64_t first_video_ts = 0, last_video_ts = 0;
    double peak = 0;
    int rate = 0, channels = 0;
    // A/V sync: rising edges of picture brightness and of audio level (100 ns units).
    int64_t flashes[MAX_EVENTS], beeps[MAX_EVENTS];
    int nflash = 0, nbeep = 0, bright = 0, loud = 0;
    int64_t quiet_since = 0;

    deadline = now_s() + timeout;
    double stop = 0;
    while (now_s() < deadline && (!stop || now_s() < stop)) {
        NDIlib_video_frame_v2_t v;
        NDIlib_audio_frame_v3_t a;
        switch (ndi->recv_capture_v3(recv, &v, &a, NULL, 200)) {
        case NDIlib_frame_type_video: {
            const uint8_t *p = v.p_data;
            if (!got_video) {
                got_video = 1;
                printf("video: %dx%d fourcc=%.4s %d/%d fps aspect=%.4f\n", v.xres, v.yres,
                       (const char *)&v.FourCC, v.frame_rate_N, v.frame_rate_D, v.picture_aspect_ratio);
                if (npx == 0) {
                    px[0][0] = v.xres / 2;
                    px[0][1] = v.yres / 2;
                    npx = 1;
                }
                for (int i = 0; i < npx; i++) {
                    int x = px[i][0] < v.xres ? px[i][0] : v.xres - 1;
                    int y = px[i][1] < v.yres ? px[i][1] : v.yres - 1;
                    const uint8_t *q = p + (size_t)y * v.line_stride_in_bytes + (size_t)x * 4;
                    printf("pixel %d,%d: r=%u g=%u b=%u a=%u\n", x, y, q[2], q[1], q[0], q[3]);
                }
                first_video_ts = v.timestamp;
                if (seconds > 0)
                    stop = now_s() + seconds;
            }
            video_frames++;
            // The first frame may be the sender's cached last frame (NDI sends it on
            // connect), so the rate is measured from the second one.
            if (video_frames == 2)
                first_video_ts = v.timestamp;
            last_video_ts = v.timestamp;
            // Brightness of the centre pixel's green channel.
            const uint8_t *c = p + (size_t)(v.yres / 2) * v.line_stride_in_bytes + (size_t)(v.xres / 2) * 4;
            int is_bright = c[1] > 128;
            if (is_bright && !bright && nflash < MAX_EVENTS)
                flashes[nflash++] = v.timestamp;
            bright = is_bright;
            ndi->recv_free_video_v2(recv, &v);
            break;
        }
        case NDIlib_frame_type_audio: {
            rate = a.sample_rate;
            channels = a.no_channels;
            audio_frames++;
            const float *s = (const float *)a.p_data;  // planar float, channel 0
            for (int i = 0; i < a.no_samples; i++) {
                double x = fabs(s[i]);
                if (x > peak) peak = x;
                int64_t ts = a.timestamp + (int64_t)i * 10000000 / a.sample_rate;
                if (x > 0.02) {
                    // Onset: loud after at least 200 ms of quiet.
                    if (!loud && ts - quiet_since > 2000000 && nbeep < MAX_EVENTS)
                        beeps[nbeep++] = ts;
                    loud = 1;
                    quiet_since = ts;
                } else if (loud && ts - quiet_since > 100000) {
                    loud = 0;  // 10 ms below the threshold ends the beep
                }
            }
            ndi->recv_free_audio_v3(recv, &a);
            break;
        }
        default:
            break;
        }
        if (got_video && seconds <= 0)
            break;
    }

    int status = got_video ? 0 : 1;
    if (!got_video)
        fprintf(stderr, "no video frame received within %.0f s\n", timeout);
    if (audio_frames)
        printf("audio: %d Hz %d ch, %d frames, peak %.3f\n", rate, channels, audio_frames, peak);
    else
        printf("audio: none\n");
    if (seconds > 0 && video_frames > 2)
        printf("video rate: %.2f fps over %d frames\n",
               (video_frames - 2) * 1e7 / (double)(last_video_ts - first_video_ts), video_frames);
    if (seconds > 0) {
        double sum = 0;
        int pairs = 0;
        for (int i = 0; i < nflash; i++) {
            int64_t best = INT64_MAX;
            for (int j = 0; j < nbeep; j++)
                if (llabs(beeps[j] - flashes[i]) < llabs(best))
                    best = beeps[j] - flashes[i];
            if (best != INT64_MAX && llabs(best) < 5000000) {  // within 0.5 s
                printf("sync: flash %d, audio %+.1f ms\n", i, best / 1e4);
                sum += best / 1e4;
                pairs++;
            }
        }
        if (pairs)
            printf("sync: mean audio offset %+.1f ms over %d events (positive = audio late)\n", sum / pairs, pairs);
        else
            printf("sync: no flash/beep pairs found (%d flashes, %d beeps)\n", nflash, nbeep);
    }
    ndi->recv_destroy(recv);
    ndi->find_destroy(find);
    return status;
}
