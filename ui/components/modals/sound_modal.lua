-- Sound settings modal.
-- Two rows: System Volume and UI Volume.
-- LEFT/RIGHT adjusts; key repeat supported via held-key timer.
-- 1% steps; caps at 100%.

local BaseModal = require("components.modals.base_modal")
local uiconfig = require("lib.uiconfig")
local T = require("lib.theme")
local hit = require("lib.hittest")

local SoundModal = {}
SoundModal.__index = SoundModal

local STEP = 0.01 -- 1% per step
local REPEAT_DELAY = 0.3 -- seconds before repeat starts
local REPEAT_RATE = 0.07 -- seconds between repeat ticks

local ROWS = {
    { id = "system", label = "System Volume" },
    { id = "ui", label = "UI Volume" },
}

local function readSystemVolume()
    local f = io.popen("wpctl get-volume @DEFAULT_SINK@ 2>/dev/null")
    if not f then
        return 0, false
    end
    local line = f:read("*l")
    f:close()
    if not line then
        return 0, false
    end
    local vol = tonumber(line:match("Volume:%s*([-0-9.]+)")) or 0
    local muted = line:find("%[MUTED%]") ~= nil
    return vol, muted
end

local function setSystemVolume(v)
    v = math.max(0.0, math.min(1.0, v)) -- cap at 100%
    os.execute(string.format("wpctl set-volume @DEFAULT_SINK@ %.2f 2>/dev/null", v))
    if _G.volumeBar then
        _G.volumeBar.syncState(v, false)
    end
    return v
end

function SoundModal.new(ui)
    local self = setmetatable({}, SoundModal)
    self.ui = ui
    self.focused = 1
    self.font = newFont(T.FONT_UI)
    self._rects = {}

    self._sys_vol, self._sys_muted = readSystemVolume()
    self._ui_vol = _G.sound and _G.sound.getVolume() or 0.5

    -- Key-repeat state: track which direction is held and for how long.
    self._held = nil -- "left" | "right" | nil
    self._held_t = 0
    self._repeat_t = 0

    local content_w = math.floor(ui.font_size * 17)
    local content_h = #ROWS * ui.item_height
    self._modal = BaseModal.new("Sound", content_w, content_h, ui)
    return self
end

function SoundModal:_getValue(id)
    if id == "system" then
        return self._sys_vol
    end
    return self._ui_vol
end

function SoundModal:_adjust(id, delta)
    if id == "system" then
        self._sys_vol = setSystemVolume(self._sys_vol + delta)
    else
        self._ui_vol = math.max(0.0, math.min(1.0, self._ui_vol + delta))
        if _G.sound then
            _G.sound.setVolume(self._ui_vol)
        end
        local cfg = uiconfig.load()
        cfg.ui_volume = self._ui_vol
        uiconfig.save(cfg)
    end
end

function SoundModal:update(inp)
    local consumed = self._modal:update(inp, function()
        _G.index.popModal()
    end)
    if consumed then
        return
    end

    local dev = inp.device()
    local n = #ROWS
    local dt = love.timer.getDelta()

    -- ── Mouse ──────────────────────────────────────────────────────── --
    if dev == "mouse" then
        local mx, my = inp.mouseX(), inp.mouseY()
        local any_hit = false
        for i, r in ipairs(self._rects) do
            if hit(mx, my, r) then
                self.focused = i
                any_hit = true
                break
            end
        end
        if not any_hit then
            self.focused = 0
        end
        if _G.cursor then
            if any_hit then
                _G.cursor.set("pointer")
            elseif not self._modal._header._focus_close then
                _G.cursor.set("normal")
            end
        end
        local dy = inp.wheelDY()
        if dy ~= 0 and self.focused >= 1 then
            self:_adjust(ROWS[self.focused].id, dy * STEP)
            if _G.sound then
                _G.sound.navigate()
            end
        end
        return
    end

    -- ── Keyboard / gamepad — UP/DOWN row navigation ─────────────────── --
    if inp.wasPressed("UP") then
        self.focused = self.focused - 1
        if self.focused < 1 then
            self.focused = n
        end
        if _G.sound then
            _G.sound.navigate()
        end
        self._held = nil
    elseif inp.wasPressed("DOWN") then
        self.focused = self.focused + 1
        if self.focused > n then
            self.focused = 1
        end
        if _G.sound then
            _G.sound.navigate()
        end
        self._held = nil
    end

    if self.focused < 1 then
        return
    end
    local row = ROWS[self.focused]

    -- ── LEFT/RIGHT with key repeat ──────────────────────────────────── --
    local left_down = love.keyboard.isDown("left")
        or (
            love.joystick.getJoysticks()[1]
            and love.joystick.getJoysticks()[1]:isGamepadDown("dpleft")
        )
    local right_down = love.keyboard.isDown("right")
        or (
            love.joystick.getJoysticks()[1]
            and love.joystick.getJoysticks()[1]:isGamepadDown("dpright")
        )

    local function doAdjust(dir)
        local delta = dir == "left" and -STEP or STEP
        self:_adjust(row.id, delta)
        if _G.sound then
            _G.sound.navigate()
        end
    end

    if inp.wasPressed("LEFT") then
        doAdjust("left")
        self._held = "left"
        self._held_t = 0
        self._repeat_t = 0
    elseif inp.wasPressed("RIGHT") then
        doAdjust("right")
        self._held = "right"
        self._held_t = 0
        self._repeat_t = 0
    elseif self._held then
        local still_held = (self._held == "left" and left_down)
            or (self._held == "right" and right_down)
        if still_held then
            self._held_t = self._held_t + dt
            if self._held_t >= REPEAT_DELAY then
                self._repeat_t = self._repeat_t + dt
                while self._repeat_t >= REPEAT_RATE do
                    self._repeat_t = self._repeat_t - REPEAT_RATE
                    doAdjust(self._held)
                end
            end
        else
            self._held = nil
        end
    end
end

function SoundModal:draw()
    local sw, sh = love.graphics.getDimensions()
    local ui = self.ui
    local ih = ui.item_height
    local area = self._modal:drawBegin(sw, sh)

    self._rects = {}
    love.graphics.setFont(self.font)

    for i, row in ipairs(ROWS) do
        local ry = area.y + (i - 1) * ih
        local focused = (i == self.focused)
        self._rects[i] = { area.x, ry, area.w, ih }

        local pad_h = T.ROW_PAD_H
        if focused then
            love.graphics.setColor(T.ROW_FOCUS_BG)
            love.graphics.rectangle("fill", area.x, ry, area.w, ih, 4, 4)
        end

        -- Label
        love.graphics.setColor(focused and T.ROW_VALUE or T.ROW_LABEL)
        love.graphics.print(row.label, area.x + pad_h, ry + (ih - self.font:getHeight()) / 2)

        -- Bar + percentage
        local val = self:_getValue(row.id)
        local pct = math.floor(val * 100 + 0.5)
        local bar_w = math.floor(area.w * 0.4)
        local bar_h = math.floor(ih * 0.18)
        local bar_x = area.x + area.w - bar_w - pad_h
        local bar_y = ry + math.floor((ih - bar_h) / 2)

        love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
        love.graphics.rectangle("fill", bar_x, bar_y, bar_w, bar_h, 2, 2)

        local fill_w = math.floor(bar_w * val)
        love.graphics.setColor(focused and T.BTN_FOCUSED or T.ROW_LABEL)
        love.graphics.rectangle("fill", bar_x, bar_y, fill_w, bar_h, 2, 2)

        local pct_str = pct .. "%"
        local pw = self.font:getWidth(pct_str)
        love.graphics.setColor(focused and T.ROW_VALUE or T.ROW_LABEL)
        love.graphics.print(
            pct_str,
            bar_x - pw - math.floor(ui.font_size * 0.3),
            ry + (ih - self.font:getHeight()) / 2
        )
    end

    self._modal:drawEnd()
end

return SoundModal
