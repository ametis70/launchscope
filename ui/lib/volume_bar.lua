-- Volume state holder.
-- Tracks volume and mute state for other widgets (notably the info bar in clock.lua).
-- Does NOT draw anything — the old bottom-right bar has been removed.
--
-- State is updated via:
--   syncState(vol, muted)    — silent background update (no animation)
--   notifyChange(vol, muted) — user-triggered change (kept for compatibility)

local M = {}

local volume = 0.0
local muted  = false

function M.load(ui_sizes)
    -- ui_sizes kept for API compatibility; not used since there's nothing to draw.
    volume = 0.0
    muted  = false
end

-- Called after a user volume/mute action.
function M.notifyChange(new_volume, new_muted)
    if new_volume ~= nil then volume = new_volume end
    if new_muted  ~= nil then muted  = new_muted  end
end

-- Called by background polls to silently sync state.
function M.syncState(new_volume, new_muted)
    if new_volume ~= nil then volume = new_volume end
    if new_muted  ~= nil then muted  = new_muted  end
end

function M.getVolume() return volume end
function M.getMuted()  return muted  end

-- Stubs kept so any caller that still references update/draw doesn't crash.
function M.update(dt) end
function M.draw()     end

return M
