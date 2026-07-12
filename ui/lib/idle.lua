-- Idle manager: dim and screen-blank on inactivity.
--
-- Configuration (all fields optional):
--   dim_timeout    number   Seconds of inactivity before dimming starts. Default: 60. 0 = disabled.
--   blank_timeout  number   Seconds of inactivity before blanking. Default: 0 (disabled).
--   blank_off      string   Shell command to turn the display off.
--   blank_on       string   Shell command to turn the display back on.
--
-- In DRM/gamescope mode, wlopm is bundled and used automatically when
-- blank_timeout > 0 and no blank_off/blank_on commands are set.
--
-- Dim: a semi-transparent black overlay drawn on top of everything in
-- index.draw(). Fades from 0 to DIM_MAX_ALPHA over DIM_FADE_DURATION seconds
-- starting at dim_timeout. Stops short of fully black so the UI remains visible.
--
-- Blank: runs blank_off once when blank_timeout elapses.
--        runs blank_on when any input arrives while blanked.
--
-- Wake grace: after waking from blank, input is blocked for WAKE_GRACE_DURATION
-- seconds so the waking keypress/button is not forwarded to the UI.
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

-- Dim fade duration (seconds) and maximum opacity (0–1).
-- Stopping at 0.85 leaves the UI faintly visible rather than going fully black.
local DIM_FADE_DURATION  = 2.0
local DIM_MAX_ALPHA      = 0.70

-- How long to ignore input after waking from blank (seconds).
local WAKE_GRACE_DURATION = 2.0

-- Default blank/unblank commands for DRM/gamescope mode.
-- wlopm is bundled via the Nix package; gamescope exposes zwlr-output-power-management-v1.
local DEFAULT_BLANK_OFF = "wlopm --off '*'"
local DEFAULT_BLANK_ON  = "wlopm --on '*'"

local _dim_timeout   = 60   -- default: 1 minute
local _blank_timeout = 0    -- default: disabled
local _blank_off     = nil
local _blank_on      = nil
local _idle_t        = 0
local _blanked       = false
local _wake_grace    = 0
local _dim_enabled   = false
local _blank_enabled = false

-- ── Helpers ───────────────────────────────────────────────────────────── --

local function runCmd(cmd)
    if cmd and cmd ~= "" then
        os.execute(cmd .. " 2>/dev/null &")
    end
end

-- ── Public API ────────────────────────────────────────────────────────── --

function M.init(cfg)
    cfg = cfg or {}
    _dim_timeout   = tonumber(cfg.dim_timeout)   or 60
    _blank_timeout = tonumber(cfg.blank_timeout) or 0
    _blank_off     = cfg.blank_off  or DEFAULT_BLANK_OFF
    _blank_on      = cfg.blank_on   or DEFAULT_BLANK_ON
    _idle_t        = 0
    _blanked       = false
    _wake_grace    = 0
    _dim_enabled   = _dim_timeout   > 0
    _blank_enabled = _blank_timeout > 0
end

-- Reset the idle timer. Call on every input event.
-- When waking from blank, starts the grace period — the waking input is
-- absorbed and not forwarded to the UI.
function M.reset()
    if _blanked then
        _blanked    = false
        _wake_grace = WAKE_GRACE_DURATION
        _idle_t     = 0
        runCmd(_blank_on)
        return
    end
    _idle_t = 0
end

-- Update timers. Call every frame from index.update(dt).
function M.update(dt)
    if _wake_grace > 0 then
        _wake_grace = math.max(0, _wake_grace - dt)
    end
    if not _dim_enabled and not _blank_enabled then return end
    _idle_t = _idle_t + dt

    if _blank_enabled and not _blanked and _idle_t >= _blank_timeout then
        _blanked    = true
        _wake_grace = 0
        runCmd(_blank_off)
    end
end

-- Draw the dim overlay. Call at the very end of index.draw().
function M.drawOverlay()
    if not _dim_enabled then return end
    if _idle_t < _dim_timeout then return end

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

-- Returns true when the display is off.
function M.isBlanked() return _blanked end

-- Returns true when the dim overlay is active (idle_t >= dim_timeout).
function M.isDimmed() return _dim_enabled and _idle_t >= _dim_timeout end

-- Returns true during the wake grace period — input should be discarded.
function M.isInputBlocked() return _wake_grace > 0 end

return M
