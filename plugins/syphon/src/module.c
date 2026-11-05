// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// "syphon": VLC 3 glue for the Syphon server. The Syphon/Metal work is in publisher.m.
//
//   vlc --video-filter=syphon movie.mp4
//   vlc --video-filter='syphon{name=Stage Left}' movie.mp4
//
// One server per VLC process, kept running while VLC is open:
//   - "syphon" control interface (Preferences > Interface > Control interfaces, or
//     --control=syphon): when the syphon video filter is enabled, starts the server at
//     launch, fully transparent at 1920x1080, before anything plays.
//   - "syphon" video filter: publishes every frame (the server follows the video's size).
//     When the video closes (end of file without Play and pause, window closed, stop),
//     the server stays up, fully transparent at the last size.
// Without the control interface, the server starts with the first video instead.
// With it, enabling or disabling the filter in Preferences applies within a second:
// the server starts or stops, and the filter is added to or removed from the video
// that is playing.

#include <vsn/plugin.h>
#include <vlc_filter.h>
#include <vlc_interface.h>
#include <vlc_picture.h>

#include <vsn/vlc3.h>
#include <vsn/vlc3_live.h>

#include "publisher.h"

#define CFG_PREFIX "syphon-"

#define NAME_TEXT N_("Server name")
#define NAME_LONGTEXT N_("Name of the Syphon server, shown in Syphon clients next to the application name.")
#define SQUARE_TEXT N_("Square pixels")
#define SQUARE_LONGTEXT N_("Scale video with non-square pixels (e.g. anamorphic DVDs) to its display aspect ratio. " \
                           "When off, frames are published at their stored size.")

// With no video, the server is fully transparent: 1920x1080 at launch, else the last size.
#define IDLE_WIDTH 1920
#define IDLE_HEIGHT 1080
// Delay before going transparent, so VLC rebuilding the filter chain (next file,
// filter changes) doesn't flash.
#define CLEAR_DELAY_MS 300

static int  OpenFilter(vlc_object_t *);
static void CloseFilter(vlc_object_t *);
static int  OpenIntf(vlc_object_t *);
static void CloseIntf(vlc_object_t *);

vlc_module_begin()
    set_shortname(N_("Syphon"))
    set_description(N_("Syphon server: share video with other applications"))
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    set_capability("video filter", 0)
    add_shortcut("syphon")
    add_string(CFG_PREFIX "name", "Video", NAME_TEXT, NAME_LONGTEXT, false)
    add_bool(CFG_PREFIX "square-pixels", true, SQUARE_TEXT, SQUARE_LONGTEXT, true)
    set_callbacks(OpenFilter, CloseFilter)

    add_submodule()
    set_shortname(N_("Syphon"))
    set_description(N_("Syphon server while VLC is open (when the Syphon video filter is enabled)"))
    set_category(CAT_INTERFACE)
    set_subcategory(SUBCAT_INTERFACE_CONTROL)
    set_capability("interface", 0)
    add_shortcut("syphon")
    set_callbacks(OpenIntf, CloseIntf)
vlc_module_end()

static const char *const filter_options[] = { "name", "square-pixels", NULL };

/* The process-wide server */

static vlc_mutex_t server_lock = VLC_STATIC_MUTEX;
static vsn_syphon *server;
static char *server_name;
static bool server_failed;  // creation failed once: don't retry on every frame
static bool shutting_down;  // control interface closed: VLC is quitting
static bool disabled;       // filter disabled in Preferences (control interface): no server

// Returns the server, creating it or renaming it as needed. Call with server_lock held.
static vsn_syphon *ServerGet(vlc_object_t *obj, const char *name)
{
    if (shutting_down || server_failed || disabled)
        return server;
    if (!name)
        name = "";
    if (!server) {
        char err[256];
        vsn_syphon_config cfg = { .name = name };
        server = vsn_syphon_create(&cfg, err, sizeof(err));
        if (!server) {
            msg_Err(obj, "cannot start the Syphon server: %s", err);
            server_failed = true;
            return NULL;
        }
        server_name = strdup(name);
        msg_Info(obj, "Syphon server \"%s\" started", name);
    } else if (!server_name || strcmp(server_name, name)) {
        vsn_syphon_set_name(server, name);
        free(server_name);
        server_name = strdup(name);
    }
    return server;
}

/* Video filter */

struct filter_sys_t {
    char *name;
    bool square_pixels;
    bool published;   // this instance showed video: clear when it closes
    unsigned errors;  // publish errors, logged sparingly
};

static void Publish(filter_t *filter, picture_t *pic)
{
    filter_sys_t *sys = filter->p_sys;
    char err[256];

    vlc_mutex_lock(&server_lock);
    vsn_syphon *s = ServerGet(VLC_OBJECT(filter), sys->name);
    if (!s || !vsn_syphon_has_clients(s)) {
        // Nobody watching: skip the conversion, but remember we're showing video so
        // a later client doesn't see an earlier idle frame as "current".
        sys->published = sys->published || s != NULL;
        vlc_mutex_unlock(&server_lock);
        return;
    }

    vsn_frame frame;
    bool ok = vsn_vlc3_frame_from_picture(&filter->fmt_in.video, pic, &frame);
    if (!ok)
        snprintf(err, sizeof(err), "cannot describe picture %4.4s",
                 (const char *)&filter->fmt_in.video.i_chroma);
    else
        ok = vsn_syphon_publish(s, &frame, sys->square_pixels, err, sizeof(err));
    sys->published = true;
    vlc_mutex_unlock(&server_lock);

    // First error, then every 300th, so a persistent problem doesn't flood the log.
    if (!ok && sys->errors++ % 300 == 0)
        msg_Warn(filter, "cannot publish frame (%u errors): %s", sys->errors, err);
}

static picture_t *Filter(filter_t *filter, picture_t *pic)
{
    if (pic)
        Publish(filter, pic);
    return pic;
}

static int OpenFilter(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;
    const video_format_t *fmt = &filter->fmt_in.video;

    // Unsupported chromas are rejected; VLC then inserts a converter in front of us.
    vsn_pixfmt pixfmt;
    vsn_memory memory;
    if (!vsn_vlc3_chroma(fmt->i_chroma, &pixfmt, &memory) || !vsn_syphon_supports(pixfmt, memory)) {
        msg_Dbg(filter, "chroma %4.4s not supported", (const char *)&fmt->i_chroma);
        return VLC_EGENERIC;
    }

    filter_sys_t *sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_ENOMEM;

    config_ChainParse(filter, CFG_PREFIX, filter_options, filter->p_cfg);
    sys->name = var_InheritString(filter, CFG_PREFIX "name");
    sys->square_pixels = var_InheritBool(filter, CFG_PREFIX "square-pixels");

    filter->p_sys = sys;
    filter->pf_video_filter = Filter;
    msg_Dbg(filter, "Syphon filter on %4.4s %ux%u", (const char *)&fmt->i_chroma,
            fmt->i_visible_width, fmt->i_visible_height);
    return VLC_SUCCESS;
}

static void CloseFilter(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;
    filter_sys_t *sys = filter->p_sys;

    // The video is gone: keep the server, fully transparent at the same size.
    vlc_mutex_lock(&server_lock);
    if (sys->published && server && !shutting_down)
        vsn_syphon_clear_later(server, CLEAR_DELAY_MS, 0, 0, 0, 0);
    vlc_mutex_unlock(&server_lock);

    free(sys->name);
    free(sys);
}

/* Control interface: the server while VLC is open, following Preferences live */

#define WATCH_INTERVAL (CLOCK_FREQ / 2)

struct intf_sys_t {
    vlc_thread_t thread;
    char *saved;  // last seen saved "video-filter" setting
};

static void StartServer(vlc_object_t *obj)
{
    char *name = var_InheritString(obj, CFG_PREFIX "name");
    vlc_mutex_lock(&server_lock);
    disabled = false;
    bool existed = server != NULL;
    vsn_syphon *s = ServerGet(obj, name);
    if (s && !existed)
        vsn_syphon_publish_color(s, IDLE_WIDTH, IDLE_HEIGHT, 0, 0, 0, 0);  // no video yet
    vlc_mutex_unlock(&server_lock);
    free(name);
}

static void StopServer(void)
{
    vlc_mutex_lock(&server_lock);
    disabled = true;
    vsn_syphon_destroy(server);
    server = NULL;
    free(server_name);
    server_name = NULL;
    vlc_mutex_unlock(&server_lock);
}

// Watches the saved setting; on a change, applies it to the server and to what plays now.
static void *Watch(void *data)
{
    intf_thread_t *intf = data;
    intf_sys_t *sys = intf->p_sys;
    for (;;) {
        msleep(WATCH_INTERVAL);
        int canc = vlc_savecancel();
        char *now = vsn_vlc3_saved_setting(VLC_OBJECT(intf), "video-filter");
        bool was = vsn_vlc3_list_has(sys->saved, "syphon");
        bool is = vsn_vlc3_list_has(now, "syphon");
        free(sys->saved);
        sys->saved = now;
        if (is != was) {
            msg_Info(intf, "Syphon %s in Preferences", is ? "enabled" : "disabled");
            if (is) {
                StartServer(VLC_OBJECT(intf));
                vsn_vlc3_apply_live(VLC_OBJECT(intf), true, "syphon", true);
            } else {
                // Remove the filter first, so it can't publish into a stopped server.
                vsn_vlc3_apply_live(VLC_OBJECT(intf), true, "syphon", false);
                StopServer();
            }
        }
        vlc_restorecancel(canc);
    }
    return NULL;
}

static int OpenIntf(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;
    intf_sys_t *sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_ENOMEM;
    intf->p_sys = sys;

    // At launch the effective setting counts (it includes command-line options);
    // later changes are watched in the saved setting, which Preferences writes.
    char *filters = var_InheritString(obj, "video-filter");
    bool enabled = vsn_vlc3_list_has(filters, "syphon");
    free(filters);
    sys->saved = vsn_vlc3_saved_setting(obj, "video-filter");

    vlc_mutex_lock(&server_lock);
    shutting_down = false;
    disabled = !enabled;
    vlc_mutex_unlock(&server_lock);
    if (enabled)
        StartServer(obj);
    else
        msg_Dbg(obj, "Syphon video filter not enabled, no server for now");

    if (vlc_clone(&sys->thread, Watch, intf, VLC_THREAD_PRIORITY_LOW)) {
        free(sys->saved);
        free(sys);
        return VLC_ENOMEM;
    }
    return VLC_SUCCESS;
}

static void CloseIntf(vlc_object_t *obj)
{
    intf_thread_t *intf = (intf_thread_t *)obj;
    intf_sys_t *sys = intf->p_sys;
    vlc_cancel(sys->thread);
    vlc_join(sys->thread, NULL);
    free(sys->saved);
    free(sys);

    // VLC is quitting: stop the server now, and don't let late video frames restart it.
    vlc_mutex_lock(&server_lock);
    shutting_down = true;
    vsn_syphon_destroy(server);
    server = NULL;
    free(server_name);
    server_name = NULL;
    vlc_mutex_unlock(&server_lock);
}
