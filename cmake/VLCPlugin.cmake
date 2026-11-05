# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Out-of-tree VLC plugin support.
#
# Provides:
#   vlc::plugin                       interface target: VLC headers, plugin defines, libvlccore link
#   vsn_add_vlc_plugin(<name> ...)    creates lib<name>_plugin.{dylib,dll,so}
#
# Headers come from third_party/vlc/<VSN_VLC_VERSION>/ (see scripts/fetch-vlc-headers.sh), so no
# VLC installation is needed to build. libvlccore is linked through a stub generated from the
# vendored libvlccore.sym:
#   macOS    a .tbd text stub with install name @rpath/libvlccore.dylib (same as official plugins)
#   Windows  an import library generated from a .def file (MinGW dlltool; MSVC lib.exe untested)
#   Linux    nothing: shared objects may keep undefined symbols, resolved by the VLC process

include_guard(GLOBAL)

set(VSN_VLC_SDK_DIR "${PROJECT_SOURCE_DIR}/third_party/vlc/${VSN_VLC_VERSION}")
if(NOT EXISTS "${VSN_VLC_SDK_DIR}/include/vlc_plugin.h")
  message(FATAL_ERROR "VLC ${VSN_VLC_VERSION} headers not found in ${VSN_VLC_SDK_DIR}. "
                      "Run: scripts/fetch-vlc-headers.sh ${VSN_VLC_VERSION}")
endif()

file(STRINGS "${VSN_VLC_SDK_DIR}/libvlccore.sym" _vsn_vlccore_symbols REGEX "^[A-Za-z_][A-Za-z0-9_]*$")

add_library(vlc_plugin_api INTERFACE)
add_library(vlc::plugin ALIAS vlc_plugin_api)
target_include_directories(vlc_plugin_api SYSTEM INTERFACE
  "${VSN_VLC_SDK_DIR}/include"
  "${VSN_VLC_SDK_DIR}/include/vlc")
# Same defines as VLC's own vlc-plugin.pc.
target_compile_definitions(vlc_plugin_api INTERFACE
  __PLUGIN__ _FILE_OFFSET_BITS=64 _REENTRANT _THREAD_SAFE)
if(WIN32)
  # VLC 3 targets Windows 7+ and uses the Unicode Win32 API.
  target_compile_definitions(vlc_plugin_api INTERFACE _WIN32_WINNT=0x0601 UNICODE _UNICODE)
endif()

if(APPLE)
  set(_tbd "${CMAKE_BINARY_DIR}/vlc-stubs/libvlccore.tbd")
  set(_targets "")
  foreach(arch IN LISTS CMAKE_OSX_ARCHITECTURES)
    list(APPEND _targets "${arch}-macos")
  endforeach()
  if(NOT _targets)
    set(_targets "${CMAKE_HOST_SYSTEM_PROCESSOR}-macos")
  endif()
  list(JOIN _targets ", " _targets)
  list(TRANSFORM _vsn_vlccore_symbols PREPEND "_" OUTPUT_VARIABLE _syms)
  list(JOIN _syms ", " _syms)
  file(CONFIGURE OUTPUT "${_tbd}" @ONLY CONTENT [[--- !tapi-tbd
tbd-version:     4
targets:         [ @_targets@ ]
install-name:    '@rpath/libvlccore.dylib'
current-version: 10.1
compatibility-version: 10
exports:
  - targets:     [ @_targets@ ]
    symbols:     [ @_syms@ ]
...
]])
  target_link_libraries(vlc_plugin_api INTERFACE "${_tbd}")

elseif(WIN32)
  set(VSN_VLCCORE_IMPORT_LIB "" CACHE FILEPATH
      "Optional libvlccore import library (e.g. sdk/lib/libvlccore.lib from the VLC win64 zip). Generated from libvlccore.sym when empty.")
  if(NOT VSN_VLCCORE_IMPORT_LIB)
    set(_def "${CMAKE_BINARY_DIR}/vlc-stubs/libvlccore.def")
    list(JOIN _vsn_vlccore_symbols "\n    " _syms)
    file(CONFIGURE OUTPUT "${_def}" @ONLY CONTENT "LIBRARY libvlccore.dll\nEXPORTS\n    @_syms@\n")
    if(MSVC)
      set(VSN_VLCCORE_IMPORT_LIB "${CMAKE_BINARY_DIR}/vlc-stubs/libvlccore.lib")
      set(_machine x64)
      if(CMAKE_SIZEOF_VOID_P EQUAL 4)
        set(_machine x86)
      elseif(CMAKE_SYSTEM_PROCESSOR MATCHES "ARM64|aarch64")
        set(_machine arm64)
      endif()
      execute_process(COMMAND "${CMAKE_AR}" /nologo /def:${_def} /machine:${_machine}
                              /out:${VSN_VLCCORE_IMPORT_LIB}
                      RESULT_VARIABLE _rc)
    else()
      find_program(VSN_DLLTOOL NAMES x86_64-w64-mingw32-dlltool llvm-dlltool dlltool REQUIRED)
      set(VSN_VLCCORE_IMPORT_LIB "${CMAKE_BINARY_DIR}/vlc-stubs/libvlccore.dll.a")
      execute_process(COMMAND "${VSN_DLLTOOL}" -d "${_def}" -l "${VSN_VLCCORE_IMPORT_LIB}" -D libvlccore.dll
                      RESULT_VARIABLE _rc)
    endif()
    if(NOT _rc EQUAL 0)
      message(FATAL_ERROR "Could not generate the libvlccore import library")
    endif()
  endif()
  target_link_libraries(vlc_plugin_api INTERFACE "${VSN_VLCCORE_IMPORT_LIB}")
endif()

# Where built plugins are collected, so VLC_PLUGIN_PATH can point at a single directory.
set(VSN_PLUGIN_OUTPUT_DIR "${CMAKE_BINARY_DIR}/out/plugins")

# vsn_add_vlc_plugin(<name> SOURCES <src>... [LINK <lib>...])
#
# <name> is the VLC module name (MODULE_STRING). The output file follows VLC's naming:
# lib<name>_plugin.dylib / .dll / .so. Plugin sources include <vsn/plugin.h> first, which sets the
# module copyright and license; that is why every plugin links vsn::vlc3.
function(vsn_add_vlc_plugin name)
  cmake_parse_arguments(ARG "" "" "SOURCES;LINK" ${ARGN})
  set(target ${name}_plugin)
  add_library(${target} MODULE ${ARG_SOURCES})
  target_link_libraries(${target} PRIVATE vsn::vlc3 ${ARG_LINK})
  target_compile_definitions(${target} PRIVATE
    MODULE_STRING="${name}"
    MODULE_NAME=${name})
  set_target_properties(${target} PROPERTIES
    PREFIX "lib"
    C_STANDARD 11
    C_EXTENSIONS ON
    C_VISIBILITY_PRESET hidden
    OBJC_VISIBILITY_PRESET hidden
    LIBRARY_OUTPUT_DIRECTORY "${VSN_PLUGIN_OUTPUT_DIR}"
    RUNTIME_OUTPUT_DIRECTORY "${VSN_PLUGIN_OUTPUT_DIR}")
  if(APPLE)
    # VLC looks for *.dylib; CMake's MODULE default on macOS is .so.
    set_target_properties(${target} PROPERTIES SUFFIX ".dylib")
    target_link_options(${target} PRIVATE "LINKER:-dead_strip")
  elseif(WIN32 AND NOT MSVC)
    target_link_options(${target} PRIVATE -static-libgcc)
  endif()
  if(CMAKE_C_COMPILER_ID MATCHES "Clang|GNU")
    target_compile_options(${target} PRIVATE -Wall -Wextra -Wno-unused-parameter)
  endif()
endfunction()
