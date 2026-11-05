# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

cmake_minimum_required(VERSION 3.24)

# Must be set before project(). Official VLC 3.0.24 for macOS is universal, minimum macOS 11.0.
if(APPLE)
  set(CMAKE_OSX_ARCHITECTURES "arm64;x86_64" CACHE STRING "macOS architectures")
  set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS version")
endif()

project(vlc-syphon-ndi VERSION 0.1.0 LANGUAGES C)
if(APPLE)
  enable_language(OBJC)
endif()

list(APPEND CMAKE_MODULE_PATH "${CMAKE_CURRENT_SOURCE_DIR}/cmake")

set(VSN_VLC_VERSION "3.0.24" CACHE STRING "VLC release whose vendored headers are used")

# Plugins. A plugin that does not support the current platform is skipped with a message.
option(VSN_BUILD_HELLO  "Build the 'hello' pass-through test filter (Phase 0)" ON)
option(VSN_BUILD_SYPHON "Build the Syphon filter (macOS)" ON)
option(VSN_BUILD_NDI    "Build the NDI filters" ON)
option(VSN_BUILD_SPOUT  "Build the Spout filter (Windows)" ON)

include(VLCPlugin)

add_subdirectory(shared)

foreach(plugin hello syphon ndi spout)
  string(TOUPPER "${plugin}" upper)
  if(VSN_BUILD_${upper} AND EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/plugins/${plugin}/CMakeLists.txt")
    add_subdirectory(plugins/${plugin})
  endif()
endforeach()
