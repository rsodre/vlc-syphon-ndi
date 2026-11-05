# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Windows x64 with MinGW-w64 (GCC or llvm-mingw), the toolchain VLC itself uses.
# Works for cross-compiling from Linux/macOS and natively in an MSYS2 shell.

set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(_prefix x86_64-w64-mingw32)

find_program(CMAKE_C_COMPILER NAMES ${_prefix}-gcc ${_prefix}-clang REQUIRED)
find_program(CMAKE_CXX_COMPILER NAMES ${_prefix}-g++ ${_prefix}-clang++)
find_program(CMAKE_RC_COMPILER NAMES ${_prefix}-windres windres)
find_program(VSN_DLLTOOL NAMES ${_prefix}-dlltool llvm-dlltool dlltool)

set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
