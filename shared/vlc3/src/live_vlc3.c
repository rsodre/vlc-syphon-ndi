// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

#include <stdlib.h>
#include <string.h>

#include <vlc_common.h>
#include <vlc_aout.h>
#include <vlc_input.h>
#include <vlc_interface.h>
#include <vlc_playlist.h>
#include <vlc_vout.h>

#include <vsn/vlc3.h>
#include <vsn/vlc3_live.h>

char *vsn_vlc3_list_with(const char *list, const char *module, bool present)
{
    size_t len = strlen(module);
    size_t cap = (list ? strlen(list) : 0) + len + 2;
    char *out = malloc(cap);
    if (!out)
        return NULL;
    out[0] = '\0';

    bool found = false;
    for (const char *p = list; p && *p; ) {
        while (*p == ':' || *p == ',' || *p == ' ')
            p++;
        if (!*p)
            break;
        const char *start = p;
        int depth = 0;  // the item ends at a separator outside {...}
        for (; *p && (depth || (*p != ':' && *p != ',')); p++) {
            if (*p == '{') depth++;
            else if (*p == '}' && depth) depth--;
        }
        size_t n = (size_t)(p - start);
        bool is_module = !strncmp(start, module, len) && (n == len || start[len] == '{');
        if (is_module) {
            if (!present || found)
                continue;  // drop it (or a duplicate)
            found = true;
        }
        if (out[0])
            strcat(out, ":");
        strncat(out, start, n);
    }
    if (present && !found) {
        if (out[0])
            strcat(out, ":");
        strcat(out, module);
    }
    return out;
}

static void update_var(vlc_object_t *obj, const char *var, const char *module, bool present)
{
    char *cur = var_GetString(obj, var);
    char *next = vsn_vlc3_list_with(cur, module, present);
    if (next && strcmp(next, cur ? cur : ""))
        var_SetString(obj, var, next);  // the vout/aout rebuilds its filters
    free(next);
    free(cur);
}

void vsn_vlc3_apply_live(vlc_object_t *intf_obj, bool video, const char *module, bool present)
{
    intf_thread_t *intf = (intf_thread_t *)intf_obj;
    playlist_t *pl = pl_Get(intf);
    if (video) {
        input_thread_t *input = playlist_CurrentInput(pl);
        if (!input)
            return;
        vout_thread_t **vouts;
        size_t count;
        if (input_Control(input, INPUT_GET_VOUTS, &vouts, &count) == VLC_SUCCESS) {
            for (size_t i = 0; i < count; i++) {
                update_var(VLC_OBJECT(vouts[i]), "video-filter", module, present);
                vlc_object_release(vouts[i]);
            }
            free(vouts);
        }
        vlc_object_release(input);
    } else {
        audio_output_t *aout = playlist_GetAout(pl);
        if (!aout)
            return;
        update_var(VLC_OBJECT(aout), "audio-filter", module, present);
        vlc_object_release(aout);
    }
}

char *vsn_vlc3_saved_setting(vlc_object_t *obj, const char *name)
{
    return config_GetPsz(obj, name);
}
