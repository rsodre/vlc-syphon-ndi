# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Bundled apps: only the launcher is compiled; packaging is apps/scripts/.
#   macOS    vsn-launcher, one binary for both apps (it reads the app's Info.plist)
#   Windows  VLCNDI.exe (the icon and version are compiled in)

if(APPLE)
  add_executable(vsn-launcher launcher/src/main.c)
  target_link_libraries(vsn-launcher PRIVATE "-framework CoreFoundation")
  set_target_properties(vsn-launcher PROPERTIES
    C_STANDARD 11
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out/apps")

elseif(WIN32)
  enable_language(RC)
  set(VSN_APP_BUILD "1" CACHE STRING "App build number: the N in the version <vlc version>-N")

  set(VSN_APP_NAME "VLCNDI")
  set(VSN_APP_VERSION "${VSN_VLC_VERSION}.${VSN_APP_BUILD}")
  string(REPLACE "." "," VSN_APP_VERSION_COMMAS "${VSN_APP_VERSION}")
  set(VSN_APP_ICON "${CMAKE_CURRENT_SOURCE_DIR}/resources/icons/${VSN_APP_NAME}.ico")
  configure_file(launcher/src/launcher.rc.in "${CMAKE_CURRENT_BINARY_DIR}/${VSN_APP_NAME}.rc" @ONLY)

  add_executable(${VSN_APP_NAME} WIN32
    launcher/src/main_windows.c
    "${CMAKE_CURRENT_BINARY_DIR}/${VSN_APP_NAME}.rc")
  set_source_files_properties("${CMAKE_CURRENT_BINARY_DIR}/${VSN_APP_NAME}.rc"
    PROPERTIES OBJECT_DEPENDS "${VSN_APP_ICON}")
  target_compile_definitions(${VSN_APP_NAME} PRIVATE UNICODE _UNICODE _WIN32_WINNT=0x0601)
  set_target_properties(${VSN_APP_NAME} PROPERTIES
    C_STANDARD 11
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/out/apps")
  if(NOT MSVC)
    # -municode: wWinMain entry point. -static: no MinGW runtime DLLs needed.
    target_link_options(${VSN_APP_NAME} PRIVATE -municode -static)
    target_compile_options(${VSN_APP_NAME} PRIVATE -Wall -Wextra)
  endif()
endif()
