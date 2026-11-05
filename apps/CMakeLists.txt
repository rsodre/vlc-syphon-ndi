# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Bundled macOS apps: only the launcher is compiled; packaging is apps/scripts/.

if(NOT APPLE)
  return()
endif()

add_executable(vsn-launcher launcher/src/main.c)
target_link_libraries(vsn-launcher PRIVATE "-framework CoreFoundation")
set_target_properties(vsn-launcher PROPERTIES
  C_STANDARD 11
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out/apps")
