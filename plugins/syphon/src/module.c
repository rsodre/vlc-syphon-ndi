// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// "syphon": VLC 3 pass-through video filter that publishes every frame through a
// Syphon server. VLC-side glue only; the Syphon/Metal work is in publisher.m.
//
//   vlc --video-filter=syphon movie.mp4
//   vlc --video-filter='syphon{name=Stage Left}' movie.mp4

#include <vsn/plugin.h>
#include <vlc_filter.h>
#include <vlc_picture.h>

#include <vsn/vlc3.h>

#include "publisher.h"

#define CFG_PREFIX "syphon-"

#define NAME_TEXT N_("Server name")
#define NAME_LONGTEXT N_("Name of the Syphon server, shown in Syphon clients next to the application name.")
#define SQUARE_TEXT N_("Square pixels")
#define SQUARE_LONGTEXT N_("Scale video with non-square pixels (e.g. anamorphic DVDs) to its display aspect ratio. " \
                           "When off, frames are published at their stored size.")

static int  Open(vlc_object_t *);
static void Close(vlc_object_t *);

vlc_module_begin()
    set_shortname(N_("Syphon"))
    set_description(N_("Syphon server: share video with other applications"))
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    set_capability("video filter", 0)
    add_shortcut("syphon")
    add_string(CFG_PREFIX "name", "Video", NAME_TEXT, NAME_LONGTEXT, false)
    add_bool(CFG_PREFIX "square-pixels", true, SQUARE_TEXT, SQUARE_LONGTEXT, true)
    set_callbacks(Open, Close)
vlc_module_end()

static const char *const filter_options[] = { "name", "square-pixels", NULL };

struct filter_sys_t {
    vsn_syphon *publisher;
    char *name;
    bool square_pixels;
    bool failed;           // server creation failed: stay a plain pass-through
    unsigned errors;       // publish errors, logged sparingly
};

static void Publish(filter_t *filter, picture_t *pic)
{
    filter_sys_t *sys = filter->p_sys;
    char err[256];

    // Created on the first frame, not in Open: VLC opens and closes the filter while
    // probing the chain, and a short-lived server would flash in clients' lists.
    if (!sys->publisher && !sys->failed) {
        vsn_syphon_config cfg = { .name = sys->name, .square_pixels = sys->square_pixels };
        sys->publisher = vsn_syphon_create(&cfg, err, sizeof(err));
        if (!sys->publisher) {
            msg_Err(filter, "cannot start the Syphon server: %s", err);
            sys->failed = true;
            return;
        }
        msg_Info(filter, "Syphon server \"%s\" started", sys->name ? sys->name : "");
    }
    if (!sys->publisher || !vsn_syphon_has_clients(sys->publisher))
        return;

    vsn_frame frame;
    if (!vsn_vlc3_frame_from_picture(&filter->fmt_in.video, pic, &frame)) {
        if (sys->errors++ == 0)
            msg_Warn(filter, "cannot describe picture %4.4s", (const char *)&filter->fmt_in.video.i_chroma);
        return;
    }
    if (!vsn_syphon_publish(sys->publisher, &frame, err, sizeof(err))) {
        // First error, then every 300th, so a persistent problem doesn't flood the log.
        if (sys->errors++ % 300 == 0)
            msg_Warn(filter, "cannot publish frame (%u errors): %s", sys->errors, err);
    }
}

static picture_t *Filter(filter_t *filter, picture_t *pic)
{
    if (pic)
        Publish(filter, pic);
    return pic;
}

static int Open(vlc_object_t *obj)
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

static void Close(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;
    filter_sys_t *sys = filter->p_sys;

    vsn_syphon_destroy(sys->publisher);
    free(sys->name);
    free(sys);
}
