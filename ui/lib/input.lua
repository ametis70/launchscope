-- Abstract input layer.
-- Maps keyboard keys, gamepad buttons/axes, and mouse to a fixed set of
-- named actions. CEC events arrive as keyboard events via cec2uinput.
--
-- Usage (each frame in update(dt)):
--   if input.wasPressed("SELECT") then ... end
--   if input.isDown("UP") then ... end
--   input.flush()   -- call once at the END of update()
--
-- Mouse-specific API:
--   input.mouseX(), input.mouseY()   current cursor position
--   input.wheelDY()                  scroll delta this frame (+up/-down)
--   input.device()                   "keyboard" | "gamepad" | "mouse"
--                                    last input device used

local M = {}

-- ── Action definitions ────────────────────────────────────────────────── --

local KEY_MAP = {
    UP           = { "up" },
    DOWN         = { "down" },
    LEFT         = { "left" },
    RIGHT        = { "right" },
    SELECT       = { "return", "kpenter" },
    BACK         = { "escape" },
    VOLUME_UP    = { "volumeup" },
    VOLUME_DOWN  = { "volumedown" },
    POWER        = { "f1" },
    SETTINGS     = { "f2" },
}

local GAMEPAD_BUTTON_MAP = {
    UP           = { "dpup" },
    DOWN         = { "dpdown" },
    LEFT         = { "dpleft" },
    RIGHT        = { "dpright" },
    SELECT       = { "a" },
    BACK         = { "b" },
    VOLUME_UP    = { "rightshoulder" },
    VOLUME_DOWN  = { "leftshoulder" },
    POWER        = { "guide" },
    SETTINGS     = { "start" },
}

local AXIS_THRESHOLD = 0.5
local AXIS_RELEASE   = AXIS_THRESHOLD * 0.6

-- ── State ─────────────────────────────────────────────────────────────── --

local pressed  = {}
local held     = {}
local axisHeld = {}

local _mouse_x    = 0
local _mouse_y    = 0
local _wheel_dy   = 0   -- scroll delta this frame
local _device     = "keyboard"  -- last active input device

-- Reverse lookups
local keyToAction    = {}
for action, keys in pairs(KEY_MAP) do
    for _, k in ipairs(keys) do keyToAction[k] = action end
end

local buttonToAction = {}
for action, btns in pairs(GAMEPAD_BUTTON_MAP) do
    for _, b in ipairs(btns) do buttonToAction[b] = action end
end

-- ── Public API ────────────────────────────────────────────────────────── --

function M.wasPressed(action)  return pressed[action] == true end
function M.isDown(action)      return held[action] == true or axisHeld[action] == true end

function M.mouseX()  return _mouse_x end
function M.mouseY()  return _mouse_y end
function M.wheelDY() return _wheel_dy end

-- Returns "keyboard", "gamepad", or "mouse" — whichever was used most recently.
function M.device()  return _device end

function M.flush()
    pressed   = {}
    _wheel_dy = 0
end

-- ── Input event handlers ─────────────────────────────────────────────── --

function M.keypressed(key)
    _device = "keyboard"
    local action = keyToAction[key]
    if action then
        pressed[action] = true
        held[action]    = true
    end
end

function M.keyreleased(key)
    local action = keyToAction[key]
    if action then held[action] = false end
end

function M.gamepadpressed(joystick, button)
    _device = "gamepad"
    local action = buttonToAction[button]
    if action then
        pressed[action] = true
        held[action]    = true
    end
end

function M.gamepadreleased(joystick, button)
    local action = buttonToAction[button]
    if action then held[action] = false end
end

function M.gamepadaxis(joystick, axis, value)
    _device = "gamepad"
    local action = nil
    local active = false

    if axis == "lefty" or axis == "righty" then
        if     value < -AXIS_THRESHOLD then action, active = "UP",   true
        elseif value >  AXIS_THRESHOLD then action, active = "DOWN", true
        elseif math.abs(value) < AXIS_RELEASE then
            axisHeld["UP"]   = false
            axisHeld["DOWN"] = false
        end
    elseif axis == "leftx" or axis == "rightx" then
        if     value < -AXIS_THRESHOLD then action, active = "LEFT",  true
        elseif value >  AXIS_THRESHOLD then action, active = "RIGHT", true
        elseif math.abs(value) < AXIS_RELEASE then
            axisHeld["LEFT"]  = false
            axisHeld["RIGHT"] = false
        end
    end

    if action and active and not axisHeld[action] then
        axisHeld[action] = true
        pressed[action]  = true
    elseif action and not active then
        axisHeld[action] = false
    end
end

function M.mousemoved(x, y)
    _mouse_x = x
    _mouse_y = y
    _device  = "mouse"
end

function M.mousepressed(x, y, button)
    _mouse_x = x
    _mouse_y = y
    _device  = "mouse"
    if button == 1 then
        pressed["SELECT"] = true
        held["SELECT"]    = true
    end
end

function M.mousereleased(x, y, button)
    if button == 1 then held["SELECT"] = false
    end
end

function M.wheelmoved(x, y)
    _device   = "mouse"
    _wheel_dy = _wheel_dy + y   -- accumulate within a frame
end

return M
