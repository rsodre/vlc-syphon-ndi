// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// "ndi": VLC 3 pass-through video and audio filters that send what VLC plays as
// an NDI source. VLC-side glue only; NDI work is in sender.c.
//
//   vlc --video-filter=ndi --audio-filter=ndi movie.mp4
//
// Both filters with the same --ndi-name feed the same NDI source.
//
// The source stays up while VLC is open:
//   - "ndi" control interface (Preferences > Interface > Control interfaces, or
//     --control=ndi): when an NDI filter is enabled, starts the source at launch with
//     a fully transparent 1920x1080 frame, before anything plays.
//   - When the video closes (end of file without Play and pause, window closed, stop),
//     the source stays up and sends a fully transparent frame at the last size.
// Without the control interface, the source starts with the first frame instead.

#include <stdatomic.h>

#include <vsn/plugin.h>
#include <vlc_aout.h>
#include <vlc_block.h>
#include <vlc_dialog.h>
#include <vlc_filter.h>
#include <vlc_interface.h>
#include <vlc_picture.h>

#include <vsn/ndi_runtime.h>
#include <vsn/vlc3.h>

#include "sender.h"
#ifdef __APPLE__
# include "cvpx_map.h"
#endif

#define CFG_PREFIX "ndi-"

#define NAME_TEXT N_("Source name")
#define NAME_LONGTEXT N_("Name of the NDI source. Receivers show it as \"COMPUTER (name)\". " \
                         "The video and audio filters with the same name form one source.")

#define BT709_TEXT N_("Convert colours to BT.709")
#define BT709_LONGTEXT N_("Re-encode SD (BT.601), BT.2020 and full-range video to BT.709 limited range, " \
                          "which NDI receivers use to decode colours. Turn off for receivers that " \
                          "decode SD video as BT.601.")

#define IDLE_WIDTH 1920
#define IDLE_HEIGHT 1080
// Delay before going transparent, so VLC rebuilding the filter chain doesn't flash.
#define CLEAR_DELAY_MS 300

static int  OpenIntf(vlc_object_t *);
static void CloseIntf(vlc_object_t *);
static int  OpenVideo(vlc_object_t *);
static void CloseVideo(vlc_object_t *);
static int  OpenAudio(vlc_object_t *);
static void CloseAudio(vlc_object_t *);

vlc_module_begin()
    set_shortname(N_("NDI"))
    set_description(N_("NDI video output: send video to the network"))
    set_category(CAT_VIDEO)
    set_subcategory(SUBCAT_VIDEO_VFILTER)
    set_capability("video filter", 0)
    add_shortcut("ndi")
    add_string(CFG_PREFIX "name", "VLC", NAME_TEXT, NAME_LONGTEXT, false)
    add_bool(CFG_PREFIX "bt709", true, BT709_TEXT, BT709_LONGTEXT, true)
    set_callbacks(OpenVideo, CloseVideo)

    add_submodule()
    set_shortname(N_("NDI"))
    set_description(N_("NDI audio output: send audio to the network"))
    set_category(CAT_AUDIO)
    set_subcategory(SUBCAT_AUDIO_AFILTER)
    set_capability("audio filter", 0)
    add_shortcut("ndi")
    set_callbacks(OpenAudio, CloseAudio)

    add_submodule()
    set_shortname(N_("NDI"))
    set_description(N_("NDI source while VLC is open (when an NDI filter is enabled)"))
    set_category(CAT_INTERFACE)
    set_subcategory(SUBCAT_INTERFACE_CONTROL)
    set_capability("interface", 0)
    add_shortcut("ndi")
    set_callbacks(OpenIntf, CloseIntf)
vlc_module_end()

static const char *const filter_options[] = { "name", "bt709", NULL };

struct filter_sys_t {
    vsn_ndi_sender *sender;
    char *name;
    bool to_bt709;
    bool video_seen;  // this video filter had a sender while video played
    mtime_t unwatched_sent;  // last frame sent while no receiver was connected
    bool failed;      // sender creation failed: stay a plain pass-through
    unsigned errors;  // send errors, logged sparingly
};

// The "runtime missing" dialog is shown once per process, not once per filter.
static atomic_bool error_shown;

// An extra reference that keeps the source up between videos, released when VLC quits.
static vlc_mutex_t keep_lock = VLC_STATIC_MUTEX;
static vsn_ndi_sender *keep;
static bool shutting_down;

static void KeepAlive(const char *name)
{
    vlc_mutex_lock(&keep_lock);
    if (!keep && !shutting_down)
        keep = vsn_ndi_sender_acquire(name, NULL, 0);
    vlc_mutex_unlock(&keep_lock);
}

// Created on the first frame, not in Open: VLC opens and closes filters while it
// builds the chain, and loading the runtime and announcing a source takes time.
static vsn_ndi_sender *GetSender(filter_t *filter)
{
    filter_sys_t *sys = filter->p_sys;
    if (sys->sender || sys->failed)
        return sys->sender;

    char err[1024];
    sys->sender = vsn_ndi_sender_acquire(sys->name, err, sizeof(err));
    if (!sys->sender) {
        sys->failed = true;
        msg_Err(filter, "%s", err);
        if (!atomic_exchange(&error_shown, true))
            vlc_dialog_display_error(filter, _("NDI output"), "%s", err);
        return NULL;
    }
    msg_Info(filter, "NDI source \"%s\" ready (runtime: %s)", sys->name ? sys->name : "",
             vsn_ndi_runtime_path());
    KeepAlive(sys->name);
    return sys->sender;
}

static int OpenCommon(filter_t *filter)
{
    filter_sys_t *sys = calloc(1, sizeof(*sys));
    if (!sys)
        return VLC_ENOMEM;
    config_ChainParse(filter, CFG_PREFIX, filter_options, filter->p_cfg);
    sys->name = var_InheritString(filter, CFG_PREFIX "name");
    sys->to_bt709 = var_InheritBool(filter, CFG_PREFIX "bt709");
    filter->p_sys = sys;
    return VLC_SUCCESS;
}

static void CloseCommon(filter_t *filter)
{
    filter_sys_t *sys = filter->p_sys;
    vsn_ndi_sender_release(sys->sender);
    free(sys->name);
    free(sys);
}

static void LogError(filter_t *filter, const char *what, const char *err)
{
    filter_sys_t *sys = filter->p_sys;
    // First error, then every 300th, so a persistent problem doesn't flood the log.
    if (sys->errors++ % 300 == 0)
        msg_Warn(filter, "%s (%u errors): %s", what, sys->errors, err);
}

/* Video */

static picture_t *FilterVideo(filter_t *filter, picture_t *pic)
{
    filter_sys_t *sys = filter->p_sys;
    if (!pic)
        return NULL;
    vsn_ndi_sender *sender = GetSender(filter);
    if (!sender)
        return pic;
    if (!sys->video_seen) {
        sys->video_seen = true;
        vsn_ndi_sender_set_size(sender, filter->fmt_in.video.i_visible_width,
                                filter->fmt_in.video.i_visible_height);
    }
    // Nobody watching: send one frame a second instead of all of them. NDI gives a new
    // receiver the last frame sent, so it starts with current video, not an idle frame.
    if (!vsn_ndi_sender_has_receivers(sender)) {
        mtime_t now = mdate();
        if (now - sys->unwatched_sent < CLOCK_FREQ)
            return pic;
        sys->unwatched_sent = now;
    }

    vsn_frame frame;
    char err[256];
    if (!vsn_vlc3_frame_from_picture(&filter->fmt_in.video, pic, &frame)) {
        LogError(filter, "cannot describe picture", "unsupported chroma");
        return pic;
    }
    // Picture dates are in VLC's system clock: the time the frame will be on screen.
    int64_t delay = pic->date > VLC_TS_INVALID ? pic->date - mdate() : 0;

#ifdef __APPLE__
    if (frame.memory == VSN_MEMORY_CVPIXELBUFFER) {
        vsn_frame cpu;
        if (!vsn_cvpx_map(&frame, &cpu)) {
            LogError(filter, "cannot send frame", "cannot map the CVPixelBuffer");
            return pic;
        }
        if (!vsn_ndi_sender_video(sender, &cpu, delay, sys->to_bt709, err, sizeof(err)))
            LogError(filter, "cannot send frame", err);
        vsn_cvpx_unmap(&frame);
        return pic;
    }
#endif
    if (!vsn_ndi_sender_video(sender, &frame, delay, sys->to_bt709, err, sizeof(err)))
        LogError(filter, "cannot send frame", err);
    return pic;
}

static void FlushVideo(filter_t *filter)
{
    filter_sys_t *sys = filter->p_sys;
    if (sys->sender)
        vsn_ndi_sender_flush(sys->sender, true, false);
}

static int OpenVideo(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;
    const video_format_t *fmt = &filter->fmt_in.video;

    // Unsupported chromas are rejected; VLC then inserts a converter in front of us.
    vsn_pixfmt pixfmt;
    vsn_memory memory;
    bool ok = vsn_vlc3_chroma(fmt->i_chroma, &pixfmt, &memory);
    if (ok && memory == VSN_MEMORY_CPU)
        ok = vsn_ndi_supports(pixfmt);
#ifdef __APPLE__
    else if (ok && memory == VSN_MEMORY_CVPIXELBUFFER)
        ok = vsn_cvpx_mappable(pixfmt);
#endif
    else
        ok = false;
    if (!ok) {
        msg_Dbg(filter, "chroma %4.4s not supported", (const char *)&fmt->i_chroma);
        return VLC_EGENERIC;
    }

    int ret = OpenCommon(filter);
    if (ret != VLC_SUCCESS)
        return ret;
    filter->pf_video_filter = FilterVideo;
    filter->pf_flush = FlushVideo;
    msg_Dbg(filter, "NDI video filter on %4.4s %ux%u", (const char *)&fmt->i_chroma,
            fmt->i_visible_width, fmt->i_visible_height);
    return VLC_SUCCESS;
}

static void CloseVideo(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;
    filter_sys_t *sys = filter->p_sys;

    // The video is gone: keep the source, send a fully transparent frame at the same size.
    vlc_mutex_lock(&keep_lock);
    if (sys->video_seen && sys->sender && !shutting_down)
        vsn_ndi_sender_clear_later(sys->sender, CLEAR_DELAY_MS);
    vlc_mutex_unlock(&keep_lock);
    CloseCommon(filter);
}

/* Audio */

static block_t *FilterAudio(filter_t *filter, block_t *block)
{
    if (!block)
        return NULL;
    vsn_ndi_sender *sender = GetSender(filter);
    if (!sender || !vsn_ndi_sender_has_receivers(sender))
        return block;

    const audio_format_t *fmt = &filter->fmt_in.audio;
    // Block dates are in VLC's system clock: the time the samples will be heard.
    int64_t delay = block->i_pts > VLC_TS_INVALID ? block->i_pts - mdate() : 0;
    if (!vsn_ndi_sender_audio(sender, (const float *)block->p_buffer, fmt->i_channels,
                              block->i_nb_samples, fmt->i_rate, delay))
        LogError(filter, "cannot send audio", "send queue full or out of memory");
    return block;
}

static void FlushAudio(filter_t *filter)
{
    filter_sys_t *sys = filter->p_sys;
    if (sys->sender)
        vsn_ndi_sender_flush(sys->sender, false, true);
}

static int OpenAudio(vlc_object_t *obj)
{
    filter_t *filter = (filter_t *)obj;

    // Ask for interleaved float; VLC converts to it before the filter.
    filter->fmt_in.audio.i_format = VLC_CODEC_FL32;
    aout_FormatPrepare(&filter->fmt_in.audio);
    filter->fmt_out.audio = filter->fmt_in.audio;

    int ret = OpenCommon(filter);
    if (ret != VLC_SUCCESS)
        return ret;
    filter->pf_audio_filter = FilterAudio;
    filter->pf_flush = FlushAudio;
    msg_Dbg(filter, "NDI audio filter on %u ch %u Hz", filter->fmt_in.audio.i_channels,
            filter->fmt_in.audio.i_rate);
    return VLC_SUCCESS;
}

static void CloseAudio(vlc_object_t *obj)
{
    CloseCommon((filter_t *)obj);
}

/* Control interface: the source while VLC is open */

static int OpenIntf(vlc_object_t *obj)
{
    char *vf = var_InheritString(obj, "video-filter");
    char *af = var_InheritString(obj, "audio-filter");
    bool video = vsn_vlc3_list_has(vf, "ndi"), audio = vsn_vlc3_list_has(af, "ndi");
    free(vf);
    free(af);
    if (!video && !audio) {
        msg_Dbg(obj, "NDI filters not enabled, no source at startup");
        return VLC_SUCCESS;  // stay loaded, harmlessly: the setting may be shared by apps
    }

    char *name = var_InheritString(obj, CFG_PREFIX "name");
    char err[1024];
    vlc_mutex_lock(&keep_lock);
    shutting_down = false;
    if (!keep)
        keep = vsn_ndi_sender_acquire(name, err, sizeof(err));
    if (keep && video)
        vsn_ndi_sender_color(keep, IDLE_WIDTH, IDLE_HEIGHT, 0, 0, 0, 0);
    vlc_mutex_unlock(&keep_lock);

    // A missing runtime is only logged here: the GUI may not be ready for dialogs yet.
    // The filters show the dialog when something plays.
    if (keep)
        msg_Info(obj, "NDI source \"%s\" started (runtime: %s)", name ? name : "",
                 vsn_ndi_runtime_path());
    else
        msg_Err(obj, "%s", err);
    free(name);
    return VLC_SUCCESS;
}

static void CloseIntf(vlc_object_t *obj)
{
    (void)obj;
    // VLC is quitting: drop the keep-alive reference; the source goes away with the
    // last filter.
    vlc_mutex_lock(&keep_lock);
    shutting_down = true;
    vsn_ndi_sender *s = keep;
    keep = NULL;
    vlc_mutex_unlock(&keep_lock);
    vsn_ndi_sender_release(s);
}
