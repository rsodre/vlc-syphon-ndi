# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

add_executable(ndi-probe src/main.c)
target_link_libraries(ndi-probe PRIVATE vsn::ndi)
if(NOT WIN32)
  target_link_libraries(ndi-probe PRIVATE m)
endif()
set_target_properties(ndi-probe PROPERTIES
  C_STANDARD 11
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out/tools")
