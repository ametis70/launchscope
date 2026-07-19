-- Idle manager: dim and screen-blank on inactivity.
--
-- Configuration (all fields optional):
--   dim_timeout    number   Seconds of inactivity before dimming starts. Default: 60. 0 = disabled.
--   blank_timeout  number   Seconds of inactivity before blanking. Default: 0 (disabled).
--   blank_mode     string   "wlopm" (default) or "cec".
--                           "wlopm" runs blank_off/blank_on shell commands.
--                           "cec" sends CEC standby/activate via the daemon's CEC API — only
--                           valid in daemon process mode. Also polls /api/cec/state to blank
--                           when the TV is off or the host PC is not the active CEC source.
--   blank_off      string   Shell command to turn the display off (blank_mode = "wlopm" only).
--   blank_on       string   Shell command to turn the display back on (blank_mode = "wlopm" only).
--   cec_poll_interval number  Seconds between /api/cec/state polls (blank_mode = "cec" only, default: 5).
--   cec_poll_mode  string   "http" (default). "ws" reserved for future WebSocket support.
--
-- In DRM/gamescope mode, wlopm is bundled and used automatically when
-- blank_timeout > 0 and no blank_off/blank_on commands are set.
--
-- Dim: a semi-transparent black overlay drawn on top of everything in
-- index.draw(). Fades from 0 to DIM_MAX_ALPHA over DIM_FADE_DURATION seconds
-- starting at dim_timeout. Stops short of fully black so the UI remains visible.
--
-- Blank: runs blank_off / CEC standby once when blank_timeout elapses.
--        runs blank_on / CEC activate when any input arrives while blanked.
--        In cec mode, also blanks when TV is off or host PC is not active source.
--
-- Wake grace: after waking from blank via input, input is blocked for
-- WAKE_GRACE_DURATION seconds so the waking keypress is not forwarded to the UI.
-- CEC-triggered wakes (TV turned on externally) do NOT start the grace period.
--
-- Usage:
--   local idle = require("lib.idle")
--   idle.init(cfg.idle)            -- call from main.lua after UI init
--   idle.reset()                   -- call on every input event
--   idle.update(dt)                -- call each frame (from index.update)
--   idle.drawOverlay()             -- call at the end of index.draw()
--   idle.isBlanked()               -- true when display is off
--   idle.isInputBlocked()          -- true during wake grace period

local M = {}

local client = require("lib.client")

-- Dim fade duration (seconds) and maximum opacity (0–1).
-- Stopping at 0.70 leaves the UI faintly visible rather than going fully black.
local DIM_FADE_DURATION = 2.0
local DIM_MAX_ALPHA = 0.70

-- How long to ignore input after waking from blank via a keypress (seconds).
-- CEC-triggered wakes skip this grace period.
local WAKE_GRACE_DURATION = 2.0

-- Default blank/unblank commands for DRM/gamescope mode.
-- wlopm is bundled via the Nix package; gamescope exposes zwlr-output-power-management-v1.
local DEFAULT_BLANK_OFF = "wlopm --off '*'"
local DEFAULT_BLANK_ON = "wlopm --on '*'"

local _dim_timeout = 60
local _blank_timeout = 0
local _blank_mode = "wlopm"
local _cec_throttle = 3.0
local _cec_throttle_t = 0
local _blank_off = nil
local _blank_on = nil
local _idle_t = 0
local _blanked = false
local _wake_grace = 0
local _dim_enabled = false
local _blank_enabled = false

-- CEC visibility polling (blank_mode = "cec" only)
local _cec_poll_interval = 5.0
local _cec_poll_t = 0
local _cec_visible = true -- optimistic: assume visible until first poll

-- ── Helpers ───────────────────────────────────────────────────────────── --

local function runCmd(cmd)
    if cmd and cmd ~= "" then
        os.execute(cmd .. " 2>/dev/null &")
    end
end

local function cecActivateThrottled()
    if _cec_throttle_t > 0 then
        return
    end
    _cec_throttle_t = _cec_throttle
    client.cecActivate()
end

-- Wake from blank without a grace period — used when visibility is restored
-- externally (TV turned on, source switched to PC) rather than by a keypress.
local function wakeExternal()
    if not _blanked then
        return
    end
    _blanked = false
    _idle_t = 0
    -- No wake grace — no keypress to absorb.
end

-- ── Public API ────────────────────────────────────────────────────────── --

function M.init(cfg)
    cfg = cfg or {}
    _dim_timeout = tonumber(cfg.dim_timeout) or 60
    _blank_timeout = tonumber(cfg.blank_timeout) or 0
    _blank_mode = cfg.blank_mode or "wlopm"
    _cec_throttle = tonumber(cfg.cec_activate_throttle) or 3.0
    _cec_throttle_t = 0
    _blank_off = cfg.blank_off or DEFAULT_BLANK_OFF
    _blank_on = cfg.blank_on or DEFAULT_BLANK_ON
    _cec_poll_interval = tonumber(cfg.cec_poll_interval) or 5.0
    _cec_poll_t = _cec_poll_interval -- poll immediately on first update
    _cec_visible = true
    _idle_t = 0
    _blanked = false
    _wake_grace = 0
    _dim_enabled = _dim_timeout > 0
    _blank_enabled = _blank_timeout > 0
end

-- Reset the idle timer. Call on every input event.
-- When waking from blank, starts the grace period — the waking input is
-- absorbed and not forwarded to the UI.
-- In cec mode, cecActivate is only sent when the display is not showing us
-- (TV off or wrong active source) — no point activating when already visible.
function M.reset()
    if _blank_mode == "cec" and not _cec_visible then
        cecActivateThrottled()
    end
    if _blanked then
        _blanked = false
        _wake_grace = WAKE_GRACE_DURATION
        _idle_t = 0
        if _blank_mode ~= "cec" then
            runCmd(_blank_on)
        end
        return
    end
    _idle_t = 0
end

-- Update timers. Call every frame from index.update(dt).
function M.update(dt)
    if _wake_grace > 0 then
        _wake_grace = math.max(0, _wake_grace - dt)
    end
    if _cec_throttle_t > 0 then
        _cec_throttle_t = math.max(0, _cec_throttle_t - dt)
    end

    -- CEC visibility poll — only in cec mode.
    if _blank_mode == "cec" then
        _cec_poll_t = _cec_poll_t + dt
        if _cec_poll_t >= _cec_poll_interval then
            _cec_poll_t = 0
            local state, err = client.get("/api/cec/state")
            if not err then
                local was_visible = _cec_visible
                _cec_visible = (state.tv_on == true) and (state.is_active_source == true)
                if _cec_visible and not was_visible then
                    -- TV turned on / source switched to PC externally — wake without grace.
                    wakeExternal()
                elseif not _cec_visible and not _blanked then
                    -- TV off or wrong source — blank immediately.
                    _blanked = true
                end
            end
        end
    end

    if not _dim_enabled and not _blank_enabled then
        return
    end
    _idle_t = _idle_t + dt

    if _blank_enabled and not _blanked and _idle_t >= _blank_timeout then
        _blanked = true
        if _blank_mode == "cec" then
            client.cecStandby()
        else
            runCmd(_blank_off)
        end
    end
end

-- Draw the dim overlay. Call at the very end of index.draw().
function M.drawOverlay()
    if not _dim_enabled then
        return
    end
    if _idle_t < _dim_timeout then
        return
    end

    local alpha
    if _idle_t >= _dim_timeout + DIM_FADE_DURATION then
        alpha = DIM_MAX_ALPHA
    else
        alpha = (_idle_t - _dim_timeout) / DIM_FADE_DURATION * DIM_MAX_ALPHA
    end

    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(0, 0, 0, alpha)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setColor(1, 1, 1, 1)
end

-- Returns true when the display is off (inactivity blank or CEC not visible).
function M.isBlanked()
    return _blanked
end

-- Returns true when the dim overlay is active (idle_t >= dim_timeout).
function M.isDimmed()
    return _dim_enabled and _idle_t >= _dim_timeout
end

-- Returns true during the wake grace period — input should be discarded.
function M.isInputBlocked()
    return _wake_grace > 0
end

return M
