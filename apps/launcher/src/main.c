// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// App launcher for VLCSyphon.app / VLCNDI.app (the bundle's CFBundleExecutable).
//
// The apps are the official, unmodified VLC with our plugins added. This launcher
// gives each app its default filters without changing VLC's code and without
// command-line options (which would override the user's preferences):
//
//   1. On first launch only, it writes a vlcrc in the app's own preferences folder,
//      ~/Library/Preferences/<bundle id>/vlcrc (VLC 3 names that folder after the
//      bundle id), turning on the filters named by the Info.plist keys
//      VSNDefaultVideoFilter and VSNDefaultAudioFilter, plus any "name=value" core
//      options listed in VSNDefaultCoreOptions (e.g. embedded-video=0).
//      On every launch it also makes sure VLC's first-run question ("Check for album art
//      and metadata?") is marked as answered, leaving online metadata off (VLC's default). That modal question, shown
//      while a file opened at first launch starts playing, made VLC lose the separate
//      video window. Users can turn metadata on in Preferences.
//   2. It replaces itself (execv) with VLC's own executable, Contents/MacOS/VLC,
//      passing all arguments through. Same process, so Finder and Apple Events work.
//
// After that the filters are ordinary VLC preferences the user can change.

#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <fcntl.h>
#include <libgen.h>
#include <limits.h>
#include <mach-o/dyld.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

static char *info_string(CFBundleRef bundle, const char *key)
{
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFBundleGetValueForInfoDictionaryKey(bundle, k);
    CFRelease(k);
    if (!v || CFGetTypeID(v) != CFStringGetTypeID() || CFStringGetLength(v) == 0)
        return NULL;
    char buf[1024];
    if (!CFStringGetCString(v, buf, sizeof(buf), kCFStringEncodingUTF8))
        return NULL;
    return strdup(buf);
}

static int mkdir_p(const char *path)
{
    char tmp[PATH_MAX];
    snprintf(tmp, sizeof(tmp), "%s", path);
    for (char *p = tmp + 1; *p; p++) {
        if (*p == '/') {
            *p = 0;
            if (mkdir(tmp, 0700) != 0 && errno != EEXIST)
                return -1;
            *p = '/';
        }
    }
    return mkdir(tmp, 0700) != 0 && errno != EEXIST ? -1 : 0;
}

// Writes each "name=value" string of the Info.plist array `key` as a line.
static int write_core_options(FILE *f, CFBundleRef bundle, const char *key)
{
    CFStringRef k = CFStringCreateWithCString(NULL, key, kCFStringEncodingUTF8);
    CFTypeRef v = CFBundleGetValueForInfoDictionaryKey(bundle, k);
    CFRelease(k);
    if (!v || CFGetTypeID(v) != CFArrayGetTypeID())
        return 0;
    int n = 0;
    for (CFIndex i = 0; i < CFArrayGetCount(v); i++) {
        CFTypeRef item = CFArrayGetValueAtIndex(v, i);
        char line[512];
        if (CFGetTypeID(item) == CFStringGetTypeID()
            && CFStringGetCString(item, line, sizeof(line), kCFStringEncodingUTF8)
            && strchr(line, '=') && !strchr(line, '\n')) {
            fprintf(f, "%s\n", line);
            n++;
        }
    }
    return n;
}

// Marks VLC's first-run question as answered (the macOS interface asks it when its
// defaults have no VLCFirstRun date).
static void skip_first_run_question(CFStringRef app_id)
{
    CFStringRef key = CFSTR("VLCFirstRun");
    CFPropertyListRef existing = CFPreferencesCopyAppValue(key, app_id);
    if (existing) {
        CFRelease(existing);
        return;
    }
    CFDateRef now = CFDateCreate(NULL, CFAbsoluteTimeGetCurrent());
    CFPreferencesSetAppValue(key, now, app_id);
    CFPreferencesAppSynchronize(app_id);
    CFRelease(now);
}

// Writes the first-run vlcrc. Never touches an existing one.
static void seed_preferences(CFBundleRef bundle)
{
    char *id = NULL, *name = info_string(bundle, "CFBundleName");
    char *vf = info_string(bundle, "VSNDefaultVideoFilter");
    char *af = info_string(bundle, "VSNDefaultAudioFilter");
    const char *home = getenv("HOME");
    CFStringRef cfid = CFBundleGetIdentifier(bundle);
    char idbuf[256];
    if (cfid && CFStringGetCString(cfid, idbuf, sizeof(idbuf), kCFStringEncodingUTF8))
        id = idbuf;
    CFTypeRef opts = CFBundleGetValueForInfoDictionaryKey(bundle, CFSTR("VSNDefaultCoreOptions"));
    if (!home || !id || (!vf && !af && !opts))
        goto out;

    char dir[PATH_MAX], path[PATH_MAX];
    snprintf(dir, sizeof(dir), "%s/Library/Preferences/%s", home, id);
    snprintf(path, sizeof(path), "%s/vlcrc", dir);
    if (access(path, F_OK) == 0 || mkdir_p(dir) != 0)
        goto out;

    int fd = open(path, O_WRONLY | O_CREAT | O_EXCL, 0600);
    if (fd < 0)
        goto out;
    FILE *f = fdopen(fd, "w");
    if (!f) {
        close(fd);
        goto out;
    }
    fprintf(f, "###\n### Created by %s on first launch: VLC's defaults plus this app's\n"
               "### defaults. VLC rewrites this file when preferences are saved.\n###\n\n"
               "[core] # core program\n", name ? name : "the app");
    write_core_options(f, bundle, "VSNDefaultCoreOptions");
    if (vf)
        fprintf(f, "video-filter=%s\n", vf);
    if (af)
        fprintf(f, "audio-filter=%s\n", af);
    fclose(f);
out:
    free(name);
    free(vf);
    free(af);
}

int main(int argc, char **argv)
{
    (void)argc;
    char self[PATH_MAX], resolved[PATH_MAX], vlc[PATH_MAX];
    uint32_t size = sizeof(self);
    if (_NSGetExecutablePath(self, &size) != 0 || !realpath(self, resolved)) {
        fprintf(stderr, "launcher: cannot find its own path\n");
        return 1;
    }
    snprintf(vlc, sizeof(vlc), "%s/VLC", dirname(resolved));

    CFBundleRef bundle = CFBundleGetMainBundle();
    if (bundle) {
        seed_preferences(bundle);
        CFStringRef id = CFBundleGetIdentifier(bundle);
        if (id)
            skip_first_run_question(id);
    }

    argv[0] = vlc;
    execv(vlc, argv);
    fprintf(stderr, "launcher: cannot start %s: %s\n", vlc, strerror(errno));
    return 1;
}
