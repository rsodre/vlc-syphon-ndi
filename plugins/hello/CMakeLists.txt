# SPDX-License-Identifier: LGPL-2.1-or-later
# Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
#
# Phase 0 feasibility test: a pass-through video filter that only logs.
# Kept as a smoke test for the build and plugin loading on every platform. Not shipped.

vsn_add_vlc_plugin(hello SOURCES src/hello.c)
