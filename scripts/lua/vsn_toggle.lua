-- SPDX-License-Identifier: LGPL-2.1-or-later
-- Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
--
-- Test interface for live enable/disable: changes the saved filter settings like
-- Preferences does (config_PutPsz). Steps come from the environment, e.g.
--   VSN_TOGGLE="3:video-filter=syphon 7:video-filter= 11:video-filter=syphon"
-- (seconds since start : option=value). Used by scripts/test-live-toggle-macos.sh.

local function wait_until(t0, seconds)
    vlc.misc.mwait(t0 + seconds * 1000000)
end

local t0 = vlc.misc.mdate()
local steps = os.getenv("VSN_TOGGLE") or ""
for at, name, value in string.gmatch(steps, "(%d+):([%w%-]+)=([^%s]*)") do
    wait_until(t0, tonumber(at))
    vlc.msg.info("vsn_toggle: " .. name .. "=" .. value)
    vlc.config.set(name, value)
end
-- Stay alive until VLC quits (it ends this thread then).
while true do
    vlc.misc.mwait(vlc.misc.mdate() + 1000000)
end
