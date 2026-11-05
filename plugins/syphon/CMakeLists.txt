# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Syphon video filter (macOS only).

if(NOT APPLE)
  message(STATUS "syphon: skipped (macOS only)")
  return()
endif()

set(SYPHON_FRAMEWORK_DIR "${PROJECT_SOURCE_DIR}/third_party/syphon/darwin")

vsn_add_vlc_plugin(syphon SOURCES src/module.c src/publisher.m)
vsn_embed_text(syphon_plugin src/shaders.metal vsn_shader_source)

target_compile_options(syphon_plugin PRIVATE
  "-F${SYPHON_FRAMEWORK_DIR}"
  $<$<COMPILE_LANGUAGE:OBJC>:-fobjc-arc>)
target_link_options(syphon_plugin PRIVATE "-F${SYPHON_FRAMEWORK_DIR}")
target_link_libraries(syphon_plugin PRIVATE
  "-framework Syphon" "-framework Metal" "-framework CoreVideo" "-framework Foundation")

# Syphon.framework is looked up next to the plugin (plugin zip, VLC_PLUGIN_PATH folder)
# or in the app's Contents/Frameworks (bundled apps: plugins live in Contents/MacOS/plugins).
set_target_properties(syphon_plugin PROPERTIES
  BUILD_RPATH "@loader_path;@loader_path/../../Frameworks"
  INSTALL_RPATH "@loader_path;@loader_path/../../Frameworks")

# Keep a copy of the framework next to the built plugins, so VLC_PLUGIN_PATH works.
add_custom_command(TARGET syphon_plugin POST_BUILD
  COMMAND rsync -a --delete "${SYPHON_FRAMEWORK_DIR}/Syphon.framework" "${VSN_PLUGIN_OUTPUT_DIR}/"
  COMMENT "Copying Syphon.framework next to the plugins")
