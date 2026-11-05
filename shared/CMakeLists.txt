# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Code shared by several plugins, as static libraries linked into each plugin.
#   vsn::core  protocol-side helpers. Must not include any VLC header.
#   vsn::vlc3  VLC 3.0.x adapter: converts VLC types to vsn::core types.
# A future VLC 4 adapter goes next to vlc3/ as vlc4/.

add_library(vsn_core STATIC core/src/frame.c)
add_library(vsn::core ALIAS vsn_core)
target_include_directories(vsn_core PUBLIC core/include)

add_library(vsn_vlc3 STATIC vlc3/src/frame_vlc3.c)
add_library(vsn::vlc3 ALIAS vsn_vlc3)
target_include_directories(vsn_vlc3 PUBLIC vlc3/include)
target_link_libraries(vsn_vlc3 PUBLIC vsn::core vlc::plugin)

foreach(lib vsn_core vsn_vlc3)
  set_target_properties(${lib} PROPERTIES
    C_STANDARD 11
    C_EXTENSIONS ON
    C_VISIBILITY_PRESET hidden
    POSITION_INDEPENDENT_CODE ON)
endforeach()
