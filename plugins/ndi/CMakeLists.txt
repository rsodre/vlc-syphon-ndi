# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# NDI video + audio filters (macOS, Windows, Linux). The NDI runtime is loaded at
# run time (shared/ndi); only the MIT-licensed headers are used at build time.

find_package(Threads REQUIRED)

set(sources src/module.c src/sender.c)
if(APPLE)
  list(APPEND sources src/cvpx_map.c)
endif()

vsn_add_vlc_plugin(ndi SOURCES ${sources} LINK vsn::ndi Threads::Threads)

if(APPLE)
  target_link_libraries(ndi_plugin PRIVATE "-framework CoreVideo")
endif()
