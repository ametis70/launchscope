-- Launchscope UI entry point.
--
-- Environment variables (set by the shell wrapper or operator):
--   LAUNCHSCOPE_SESSION_MODE   drm_gamescope | nested_gamescope | nested_direct
--   LAUNCHSCOPE_PROCESS_MODE   daemon | standalone
--   LAUNCHSCOPE_PORT=N         Override server port (default 8765)
--   LAUNCHSCOPE_FONT=name      Override font from config (name or absolute path)

local uiconfig = require("lib.uiconfig")
local client = require("lib.client")
local input = require("lib.input")
local shader = require("lib.shader")
local volumeBar = require("lib.volume_bar")
local icons = require("lib.icons")
local cursor = require("lib.cursor")
local sound = require("lib.sound")
local T = require("lib.theme")
local idle = require("lib.idle")
local index = require("index")

-- Expose cursor globally so views and modals can switch cursors.
_G.cursor = nil -- set after init

-- Expose index globally so views and modals can push modals / switch views.
_G.index = index

local NESTED = os.getenv("LAUNCHSCOPE_SESSION_MODE") == "nested_gamescope"
    or os.getenv("LAUNCHSCOPE_SESSION_MODE") == "nested_direct"

-- ── Volume polling via wpctl ──────────────────────────────────────────── --

local function readVolumeWpctl()
    local f = io.popen("wpctl get-volume @DEFAULT_SINK@ 2>/dev/null")
    if not f then
        return nil, nil
    end
    local line = f:read("*l")
    f:close()
    if not line then
        return nil, nil
    end
    local vol = tonumber(line:match("Volume:%s*([-0-9.]+)"))
    local muted = line:find("%[MUTED%]") ~= nil
    return vol, muted
end

-- ── Globals ───────────────────────────────────────────────────────────── --

_G.volumeBar = volumeBar

local _font_path = nil

local function resolveFontPath(spec)
    if not spec or spec == "" then
        return nil
    end
    if spec:sub(1, 1) == "/" then
        local fh = io.open(spec, "rb")
        if fh then
            fh:close()
            return spec
        end
        print("WARNING: font file not found: " .. spec)
        return nil
    end
    local fh = io.popen("fc-match --format='%{file}' '" .. spec:gsub("'", "") .. "' 2>/dev/null")
    if not fh then
        print("WARNING: fc-match not available, cannot resolve font name: " .. spec)
        return nil
    end
    local path = fh:read("*l")
    fh:close()
    if not path or path == "" then
        print("WARNING: fc-match could not resolve font: " .. spec)
        return nil
    end
    return path
end

local function _loadFont(size)
    local f
    if not _font_path then
        f = love.graphics.newFont(size, "none")
    else
        local fh = io.open(_font_path, "rb")
        if not fh then
            print("WARNING: cannot open font file: " .. _font_path .. " — using default")
            _font_path = nil
            f = love.graphics.newFont(size, "none")
        else
            local data = fh:read("*a")
            fh:close()
            local fd = love.filesystem.newFileData(data, "font.ttf")
            f = love.graphics.newFont(fd, size, "none")
        end
    end
    f:setFilter("nearest", "nearest")
    return f
end

-- Global font constructor used by all components, views, and modals.
function newFont(size)
    return _loadFont(size)
end

-- ── love callbacks ────────────────────────────────────────────────────── --

local cfg = nil
local _vol_poll_timer = 0
local VOL_POLL_RATE = 2.0

function love.load()
    if love.filesystem.getInfo("assets/gamecontrollerdb.txt") then
        love.joystick.loadGamepadMappings("assets/gamecontrollerdb.txt")
    end
    cfg = uiconfig.load()
    _init()
    local vol, mut = readVolumeWpctl()
    if vol then
        volumeBar.syncState(vol, mut)
    end
end

function love.update(dt)
    -- While blanked (inactivity or CEC not visible), skip UI rendering work
    -- but still update idle so CEC polling can detect when to wake.
    if _G.idle and _G.idle.isBlanked() then
        if _G.idle then
            _G.idle.update(dt)
        end
        input.flush()
        love.timer.sleep(0.1)
        return
    end

    -- Hide the cursor as soon as the dim overlay starts.
    if _G.idle and _G.idle.isDimmed() then
        if _G.cursor then
            _G.cursor.hideDim()
        end
    end

    shader.update(dt)

    if cfg and cfg.process_mode ~= "daemon" then
        _vol_poll_timer = _vol_poll_timer + dt
        if _vol_poll_timer >= VOL_POLL_RATE then
            _vol_poll_timer = 0
            local vol, mut = readVolumeWpctl()
            if vol then
                volumeBar.syncState(vol, mut)
            end
        end
    end

    index.update(dt)
    -- NOTE: input.flush() is called inside index.update()
end

function love.draw()
    if _G.idle and _G.idle.isBlanked() then
        return
    end
    index.draw()
end

function love.keypressed(key)
    if key == "q" and love.keyboard.isDown("lctrl") then
        love.event.quit()
    end
    if _G.cursor then
        _G.cursor.hide()
    end
    if _G.idle then
        _G.idle.reset()
    end
    if _G.idle and _G.idle.isInputBlocked() then
        return
    end
    index.keypressed(key)
    input.keypressed(key)
end

function love.keyreleased(key)
    input.keyreleased(key)
end
function love.gamepadpressed(j, b)
    if _G.cursor then
        _G.cursor.hide()
    end
    if _G.idle then
        _G.idle.reset()
    end
    if _G.idle and _G.idle.isInputBlocked() then
        return
    end
    input.gamepadpressed(j, b)
end
function love.gamepadreleased(j, b)
    input.gamepadreleased(j, b)
end
function love.gamepadaxis(j, a, v)
    if _G.cursor then
        _G.cursor.hide()
    end
    if _G.idle then
        _G.idle.reset()
    end
    if _G.idle and _G.idle.isInputBlocked() then
        return
    end
    input.gamepadaxis(j, a, v)
end
function love.mousemoved(x, y)
    if _G.cursor then
        if _G.cursor.isHiddenByDim() then
            _G.cursor.showDim()
        else
            _G.cursor.show()
        end
    end
    if _G.idle then
        _G.idle.reset()
    end
    input.mousemoved(x, y)
end

function love.mousepressed(x, y, b)
    -- If the cursor was hidden by the dim overlay, this click is only waking
    -- the cursor — show it and reset idle, but do not forward to the UI.
    if _G.cursor and _G.cursor.isHiddenByDim() then
        _G.cursor.showDim()
        if _G.idle then
            _G.idle.reset()
        end
        return
    end
    if _G.idle then
        _G.idle.reset()
    end
    if _G.idle and _G.idle.isInputBlocked() then
        return
    end
    input.mousepressed(x, y, b)
end
function love.mousereleased(x, y, b)
    input.mousereleased(x, y, b)
end
function love.wheelmoved(x, y)
    if _G.idle then
        _G.idle.reset()
    end
    if _G.idle and _G.idle.isInputBlocked() then
        return
    end
    input.wheelmoved(x, y)
end
function love.textinput(_) end

function love.resize(w, h)
    shader.applyConfig(cfg and cfg.background)
    index.resize(w, h)
end

-- ── Private ───────────────────────────────────────────────────────────── --

function _init()
    local disp = cfg.display or {}
    local out = disp.output or {}

    if not NESTED then
        -- drm_gamescope: gamescope controls the display; just set the window size.
        local fs = true
        local w = out.width or 1920
        local h = out.height or 1080
        love.window.setMode(w, h, {
            fullscreen = fs,
            fullscreentype = "desktop",
            vsync = 1,
        })
    else
        -- nested_gamescope / nested_direct: fullscreen is user-controlled.
        local fs = disp.fullscreen ~= false
        local w = out.width or 1920
        local h = out.height or 1080
        love.window.setMode(w, h, {
            fullscreen = fs,
            fullscreentype = "desktop",
            vsync = 1,
        })
    end

    _font_path = resolveFontPath(os.getenv("LAUNCHSCOPE_FONT") or cfg.font)

    local scale = cfg.scale or 1.0
    _G.UI = {
        font_size = math.floor(38 * scale),
        icon_size = math.floor(24 * scale), -- cursor size only
        ui_icon_size = math.floor(24 * scale), -- all UI icons
        item_height = math.floor(72 * scale),
        padding = math.floor(24 * scale),
        corner_padding = math.floor(32 * scale),
    }
    T.init(_G.UI)

    -- Icons singleton uses ui_icon_size (half of icon_size).
    -- Cursors keep the full icon_size so they remain crisp at cursor scale.
    local icon_size = cfg.icon_size or _G.UI.ui_icon_size
    local icon_mode = cfg.icons or "unicode"
    icons.init(icon_mode, icon_size, newFont(icon_size))

    cursor.init(_G.UI.icon_size)
    _G.cursor = cursor

    sound.load(cfg.ui_volume or 0.5)
    _G.sound = sound

    idle.init(cfg.idle)
    _G.idle = idle

    if
        cfg.process_mode == "daemon"
        and cfg.idle
        and cfg.idle.blank_mode == "cec"
        and cfg.idle.cec_activate_on_start ~= false
    then
        client.cecActivate()
    end

    if cfg.background then
        shader.load(cfg.background)
    end

    volumeBar.load(_G.UI)

    index.init(cfg, _G.UI)
end
