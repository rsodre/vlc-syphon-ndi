// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// App launcher for VLCNDI on Windows (VLCNDI.exe, next to the official vlc.exe).
//
// The app is the official, unmodified VLC for Windows with our plugin added. Like the
// macOS launcher (main.c), this one gives the app its default filters without changing
// VLC's code and without command-line options (which would override the user's
// preferences):
//
//   1. It makes sure the folder "portable" exists next to vlc.exe. VLC for Windows keeps
//      its settings and caches there when it exists (VLC's own portable mode), instead of
//      %APPDATA%\vlc, so the app has its own settings, separate from an installed VLC.
//   2. On first launch only (no portable\vlcrc yet), it copies <launcher name>-defaults.vlcrc
//      (written by apps/scripts/package-windows.sh from the app's app.conf) to
//      portable\vlcrc.
//   3. When plugins\plugins.dat is missing (first launch: the zip has none, like VideoLAN's
//      zip), it runs VLC's own vlc-cache-gen.exe to write it, as VLC's installer does.
//      Without that cache VLC loads every plugin at each start, which takes seconds.
//   4. It starts vlc.exe with the same arguments, waits for it and returns its exit code.
//
// After that the filters are ordinary VLC preferences the user can change.

#include <windows.h>
#include <wchar.h>

#define PATH_CHARS 32768

static void fail(const wchar_t *app, const wchar_t *what, const wchar_t *path)
{
    static wchar_t msg[PATH_CHARS + 512];
    _snwprintf(msg, sizeof(msg) / sizeof(*msg) - 1, L"%ls\n\n%ls", what, path);
    MessageBoxW(NULL, msg, app, MB_OK | MB_ICONERROR);
}

// The command line after the program name, as Windows passed it (quoting kept).
static const wchar_t *arguments(void)
{
    const wchar_t *p = GetCommandLineW();
    if (*p == L'"') {
        for (p++; *p && *p != L'"'; p++) {}
        if (*p)
            p++;
    } else {
        while (*p && *p != L' ' && *p != L'\t')
            p++;
    }
    while (*p == L' ' || *p == L'\t')
        p++;
    return p;
}

// Runs a command line and waits for it. Returns the exit code, or -1 if it didn't start.
static int run(wchar_t *command, DWORD flags)
{
    STARTUPINFOW si;
    PROCESS_INFORMATION pi;
    GetStartupInfoW(&si);
    if (!CreateProcessW(NULL, command, NULL, NULL, TRUE, flags, NULL, NULL, &si, &pi))
        return -1;
    CloseHandle(pi.hThread);
    WaitForSingleObject(pi.hProcess, INFINITE);
    DWORD code = 1;
    GetExitCodeProcess(pi.hProcess, &code);
    CloseHandle(pi.hProcess);
    return (int)(code & 0x7fffffff);
}

int WINAPI wWinMain(HINSTANCE inst, HINSTANCE prev, PWSTR cmdline, int show)
{
    (void)inst; (void)prev; (void)cmdline; (void)show;
    static wchar_t self[PATH_CHARS], dir[PATH_CHARS], app[MAX_PATH], path[PATH_CHARS],
                   defaults[PATH_CHARS], command[PATH_CHARS];

    DWORD n = GetModuleFileNameW(NULL, self, PATH_CHARS);
    wchar_t *slash = n && n < PATH_CHARS ? wcsrchr(self, L'\\') : NULL;
    if (!slash) {
        fail(L"VLC launcher", L"Cannot find the launcher's own path.", L"");
        return 1;
    }
    wcsncpy(dir, self, slash - self);
    dir[slash - self] = 0;
    wcsncpy(app, slash + 1, MAX_PATH - 1);
    wchar_t *dot = wcsrchr(app, L'.');
    if (dot)
        *dot = 0;

    _snwprintf(path, PATH_CHARS - 1, L"%ls\\vlc.exe", dir);
    if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) {
        fail(app, L"vlc.exe is missing. Keep this program in its folder, next to vlc.exe:", path);
        return 1;
    }

    // Settings folder (VLC's portable mode) and first-launch defaults.
    _snwprintf(path, PATH_CHARS - 1, L"%ls\\portable", dir);
    if (!CreateDirectoryW(path, NULL) && GetLastError() != ERROR_ALREADY_EXISTS) {
        fail(app, L"Cannot create the settings folder. Move this program's folder to a place "
                  L"where you can save files (for example Documents, not Program Files):", path);
        return 1;
    }
    _snwprintf(path, PATH_CHARS - 1, L"%ls\\portable\\vlcrc", dir);
    _snwprintf(defaults, PATH_CHARS - 1, L"%ls\\%ls-defaults.vlcrc", dir, app);
    // Fails when vlcrc exists (never overwritten) or when there is no defaults file.
    CopyFileW(defaults, path, TRUE);

    // Plugin cache, written once by VLC's own tool (no window).
    _snwprintf(path, PATH_CHARS - 1, L"%ls\\plugins\\plugins.dat", dir);
    if (GetFileAttributesW(path) == INVALID_FILE_ATTRIBUTES) {
        _snwprintf(command, PATH_CHARS - 1, L"\"%ls\\vlc-cache-gen.exe\" \"%ls\\plugins\"", dir, dir);
        run(command, CREATE_NO_WINDOW);
    }

    _snwprintf(command, PATH_CHARS - 1, L"\"%ls\\vlc.exe\" %ls", dir, arguments());
    int code = run(command, 0);
    if (code < 0) {
        _snwprintf(path, PATH_CHARS - 1, L"%ls\\vlc.exe", dir);
        fail(app, L"Cannot start VLC:", path);
        return 1;
    }
    return code;
}
