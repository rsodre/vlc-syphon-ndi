# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors

set(SYPHON_FRAMEWORK_DIR "${PROJECT_SOURCE_DIR}/third_party/syphon/darwin")

add_executable(syphon-probe src/main.m)
target_compile_options(syphon-probe PRIVATE -fobjc-arc "-F${SYPHON_FRAMEWORK_DIR}")
target_link_options(syphon-probe PRIVATE "-F${SYPHON_FRAMEWORK_DIR}")
target_link_libraries(syphon-probe PRIVATE
  "-framework Syphon" "-framework Metal" "-framework Foundation" "-framework AppKit"
  "-framework CoreGraphics" "-framework ImageIO" "-framework UniformTypeIdentifiers")
set_target_properties(syphon-probe PROPERTIES
  BUILD_RPATH "${SYPHON_FRAMEWORK_DIR}"
  RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out/tools")
