// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// Include first in every plugin's module file: sets the copyright and license
// that VLC shows for the module, then pulls in the VLC plugin API.

#ifndef VSN_PLUGIN_H
#define VSN_PLUGIN_H

#define VLC_MODULE_COPYRIGHT "Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors"
#define VLC_MODULE_LICENSE VLC_LICENSE_LGPL_2_1_PLUS

#include <vlc_common.h>
#include <vlc_plugin.h>

// VLC defines these in vlc_fixups.h, which needs VLC's own config.h. Our strings are not
// in VLC's translation catalog, so N_() only marks them and _() falls back to English.
#ifndef N_
# define N_(str) (str)
#endif
#ifndef _
# define _(str) vlc_gettext(str)
#endif

#endif
