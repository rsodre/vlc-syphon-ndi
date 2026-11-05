// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// "hello": pass-through video filter for the Phase 0 feasibility test.
// Returns every picture untouched and logs what it sees, which proves that an
// out-of-tree plugin builds against the vendored headers and loads in VLC.
//
//   vlc --video-filter=hello -vv <file>

#include <vsn/plugin.h>
#include <vlc_filter.h>
#include <vlc_picture.h>
#include <vlc/libvlc_version.h>

#include <vsn/vlc3.h>

static int  Open(vlc_object_t *);
static void Close(vlc_object_t *);

vlc_module_begin()
    set_shortname("Hello")
    set_description("vlc-syphon-ndi pass-through test filter")
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    set_capability("video filter", 0)
    add_shortcut("hello")
    set_callbacks(Open, Close)
vlc_module_end()

struct filter_sys_t {
    uint64_t frames;
};

static picture_t *Filter(filter_t *filter, picture_t *pic)
{
    filter_sys_t *sys = filter->p_sys;

    if (pic && sys->frames++ == 0) {
        vsn_frame frame;
        if (vsn_vlc3_frame_from_picture(&filter->fmt_in.video, pic, &frame))
            msg_Info(filter, "first frame: %ux%u %s in %s memory, %d plane(s), pts %" PRId64,
                     frame.width, frame.height, vsn_pixfmt_name(frame.pixfmt),
                     vsn_memory_name(frame.memory), frame.plane_count, frame.pts_us);
        else
            msg_Info(filter, "first frame: unsupported chroma %4.4s",
                     (const char *)&filter->fmt_in.video.i_chroma);
    }
    return pic;
}

static int Open(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;

    filter_sys_t *sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_ENOMEM;
    filter->p_sys = sys;
    filter->pf_video_filter = Filter;

    const video_format_t *fmt = &filter->fmt_in.video;
    msg_Info(filter, "hello from vlc-syphon-ndi (built against VLC %d.%d.%d): %4.4s %ux%u",
             LIBVLC_VERSION_MAJOR, LIBVLC_VERSION_MINOR, LIBVLC_VERSION_REVISION,
             (const char *)&fmt->i_chroma, fmt->i_visible_width, fmt->i_visible_height);
    return VLC_SUCCESS;
}

static void Close(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;
    filter_sys_t *sys = filter->p_sys;

    msg_Info(filter, "goodbye after %" PRIu64 " frame(s)", sys->frames);
    free(sys);
}
