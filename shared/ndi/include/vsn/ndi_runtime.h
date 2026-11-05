// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// Loads the user-installed NDI 6 runtime at run time. The runtime is proprietary
// and never bundled or linked; we only compile against the MIT-licensed headers.
// No VLC headers here.

#ifndef VSN_NDI_RUNTIME_H
#define VSN_NDI_RUNTIME_H

#include <stdbool.h>
#include <stddef.h>

#include <Processing.NDI.Lib.h>

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Loads and initializes the runtime once per process; later calls return the
 * same table. The library is never unloaded. Thread-safe.
 * Searches $NDI_RUNTIME_DIR_V6 first, then the platform's default install location.
 * Returns NULL and writes a message (including the paths tried) to err on failure.
 */
const NDIlib_v6 *vsn_ndi_load(char *err, size_t err_size);

/** Path of the loaded runtime, or NULL if not loaded. */
const char *vsn_ndi_runtime_path(void);

/** Where users can download the runtime. */
const char *vsn_ndi_runtime_url(void);

#ifdef __cplusplus
}
#endif

#endif
