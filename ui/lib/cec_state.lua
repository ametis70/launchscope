-- CEC display state tracker for the UI.
--
-- Only active when process_mode = "daemon" and blank_mode = "cec".
-- Polls /api/cec/state via HTTP and tracks whether the display is visible
-- (TV on AND host PC is the active CEC source).
--
-- When the display becomes visible after being hidden, idle is reset
-- immediately so the dim overlay clears without waiting for input.
--
-- Configuration (from cfg.idle):
--   cec_poll_interval  number   Seconds between HTTP polls (default: 5)
--   cec_poll_mode      string   "http" (default) — "ws" reserved for future use
--
-- Public API:
--   M.init(cfg, idle)   call from main.lua after idle.init()
--   M.update(dt)        call every frame from love.update()
--   M.isVisible()       true when TV is on AND host PC is active source

local client = require("lib.client")

local M = {}

local _enabled       = false
local _idle          = nil
local _poll_interval = 5.0
local _poll_t        = 0
local _visible       = true   -- optimistic default so UI shows on startup

function M.init(cfg, idle_mod)
    local process_mode = cfg and cfg.process_mode or "standalone"
    local blank_mode   = cfg and cfg.idle and cfg.idle.blank_mode or "wlopm"
    if process_mode ~= "daemon" or blank_mode ~= "cec" then
        _enabled = false
        return
    end
    _enabled       = true
    _idle          = idle_mod
    _poll_interval = (cfg.idle and tonumber(cfg.idle.cec_poll_interval)) or 5.0
    _poll_t        = _poll_interval  -- poll immediately on first update
    _visible       = true
end

function M.update(dt)
    if not _enabled then return end
    _poll_t = _poll_t + dt
    if _poll_t < _poll_interval then return end
    _poll_t = 0

    local state, err = client.get("/api/cec/state")
    if err then
        -- Server unreachable — stay with last known state
        return
    end

    local was_visible = _visible
    _visible = (state.tv_on == true) and (state.is_active_source == true)

    -- Became visible — clear dim/blank immediately without waiting for input.
    if _visible and not was_visible then
        if _idle then _idle.reset() end
    end
end

function M.isVisible()
    if not _enabled then return true end
    return _visible
end

return M
