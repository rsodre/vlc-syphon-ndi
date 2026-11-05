# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# cmake -DINPUT=<file> -DOUTPUT=<header> -DNAME=<symbol> -P embed-text.cmake
# Writes `static const char <NAME>[] = { ..., 0 };` with the file's bytes.

file(READ "${INPUT}" hex HEX)
string(REGEX REPLACE "([0-9a-f][0-9a-f])" "0x\\1," bytes "${hex}")
string(REGEX REPLACE "(0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,0x..,)" "\\1\n    " bytes "${bytes}")
get_filename_component(src "${INPUT}" NAME)
file(WRITE "${OUTPUT}.tmp"
  "// Generated from ${src} by cmake/scripts/embed-text.cmake. Do not edit.\n"
  "static const char ${NAME}[] = {\n    ${bytes}0x00\n};\n")
file(COPY_FILE "${OUTPUT}.tmp" "${OUTPUT}" ONLY_IF_DIFFERENT)
file(REMOVE "${OUTPUT}.tmp")
