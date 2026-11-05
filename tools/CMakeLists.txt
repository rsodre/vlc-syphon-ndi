# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Developer tools used by the tests. Not shipped.

if(APPLE AND VSN_BUILD_SYPHON)
  add_subdirectory(syphon-probe)
endif()
