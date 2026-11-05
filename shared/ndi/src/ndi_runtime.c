// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifdef _WIN32
# include <windows.h>
#else
# include <dlfcn.h>
# include <pthread.h>
#endif

#include <vsn/ndi_runtime.h>

typedef const NDIlib_v6 *(*load_fn)(void);

// Default install locations, tried after $NDI_RUNTIME_DIR_V6.
static const char *const default_paths[] = {
#if defined(__APPLE__)
    "/usr/local/lib/" NDILIB_LIBRARY_NAME,                   // NDI Runtime / NDI Tools installer
    "/Library/NDI SDK for Apple/lib/macOS/" NDILIB_LIBRARY_NAME,
    NDILIB_LIBRARY_NAME,                                      // dyld default search
#elif defined(_WIN32)
    NDILIB_LIBRARY_NAME,                                      // DLL search path
#else
    NDILIB_LIBRARY_NAME,                                      // ld.so search path
    "/usr/local/lib/" NDILIB_LIBRARY_NAME,
    "/usr/lib/" NDILIB_LIBRARY_NAME,
#endif
    NULL,
};

#ifdef _WIN32
static CRITICAL_SECTION lock;
static INIT_ONCE lock_once = INIT_ONCE_STATIC_INIT;
static BOOL CALLBACK init_lock(PINIT_ONCE o, PVOID p, PVOID *c)
{
    (void)o; (void)p; (void)c;
    InitializeCriticalSection(&lock);
    return TRUE;
}
static void lock_acquire(void) { InitOnceExecuteOnce(&lock_once, init_lock, NULL, NULL); EnterCriticalSection(&lock); }
static void lock_release(void) { LeaveCriticalSection(&lock); }

static load_fn open_runtime(const char *path)
{
    HMODULE h = LoadLibraryA(path);
    if (!h)
        return NULL;
    load_fn fn = (load_fn)(void *)GetProcAddress(h, "NDIlib_v6_load");
    if (!fn)
        FreeLibrary(h);
    return fn;
}
#else
static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
static void lock_acquire(void) { pthread_mutex_lock(&lock); }
static void lock_release(void) { pthread_mutex_unlock(&lock); }

static load_fn open_runtime(const char *path)
{
    void *h = dlopen(path, RTLD_LOCAL | RTLD_NOW);
    if (!h)
        return NULL;
    load_fn fn = (load_fn)dlsym(h, "NDIlib_v6_load");
    if (!fn)
        dlclose(h);
    return fn;
}
#endif

static const NDIlib_v6 *loaded;
static char loaded_path[1024];

const NDIlib_v6 *vsn_ndi_load(char *err, size_t err_size)
{
    lock_acquire();
    if (loaded) {
        lock_release();
        return loaded;
    }

    char tried[2048] = "";
    char path[1024];
    const NDIlib_v6 *lib = NULL;

    const char *dir = getenv(NDILIB_REDIST_FOLDER);
    for (int i = -1; !lib && (i < 0 || default_paths[i]); i++) {
        if (i < 0) {
            if (!dir || !*dir)
                continue;
#ifdef _WIN32
            snprintf(path, sizeof(path), "%s\\%s", dir, NDILIB_LIBRARY_NAME);
#else
            snprintf(path, sizeof(path), "%s/%s", dir, NDILIB_LIBRARY_NAME);
#endif
        } else {
            snprintf(path, sizeof(path), "%s", default_paths[i]);
        }
        size_t used = strlen(tried);
        snprintf(tried + used, sizeof(tried) - used, "%s%s", used ? ", " : "", path);

        load_fn fn = open_runtime(path);
        if (fn)
            lib = fn();
    }

    if (!lib) {
        if (err)
            snprintf(err, err_size, "NDI 6 runtime not found (tried: %s). Install it from %s",
                     tried, vsn_ndi_runtime_url());
    } else if (!lib->initialize()) {
        if (err)
            snprintf(err, err_size, "NDI runtime at %s failed to initialize (unsupported CPU?)", path);
        lib = NULL;
    } else {
        loaded = lib;
        snprintf(loaded_path, sizeof(loaded_path), "%s", path);
    }
    lock_release();
    return lib;
}

const char *vsn_ndi_runtime_path(void)
{
    return loaded ? loaded_path : NULL;
}

const char *vsn_ndi_runtime_url(void)
{
    return "https://ndi.video/tools/";
}
