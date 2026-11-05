// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// VLC 3: apply filter changes to what is playing now, so enabling or disabling a
// plugin in Preferences works without replaying or restarting.

#ifndef VSN_VLC3_LIVE_H
#define VSN_VLC3_LIVE_H

#include <vlc_common.h>

/**
 * Returns a new module list (free() it) with module added at the end (present) or
 * removed with its {options} (!present). Other entries are kept as they are.
 */
char *vsn_vlc3_list_with(const char *list, const char *module, bool present);

/**
 * Adds or removes module in the filter list of what the playlist is playing now:
 * every video output ("video-filter") when video, else the audio output ("audio-filter").
 * VLC rebuilds those filters immediately. intf must be an interface object.
 */
void vsn_vlc3_apply_live(vlc_object_t *intf, bool video, const char *module, bool present);

/** The setting as saved by Preferences (ignores command-line overrides). free() it. */
char *vsn_vlc3_saved_setting(vlc_object_t *obj, const char *name);

#endif
