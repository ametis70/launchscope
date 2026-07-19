-- Scrollable vertical list.
-- Items: { id = string, label = string }
-- Internally tracks item rects for mouse hit-testing — callers never need
-- to manage _list_item_rects themselves.
--
-- Constructor opts:
--   x, y, width, height   layout
--   ui                    global UI sizing table
--   font                  (optional) love.Font override
--   on_select             function(item) called on SELECT

local T = require("lib.theme")
local hit = require("lib.hittest")

local List = {}
List.__index = List

function List.new(items, opts)
    local self = setmetatable({}, List)
    self.x = opts.x or 0
    self.y = opts.y or 0
    self.width = opts.width or 400
    self.ui = opts.ui
    self.font = opts.font or newFont(T.FONT_LG)
    self.on_select = opts.on_select
    self.item_h = self.ui.item_height
    self.arrow_h = math.floor(self.item_h * 0.6)
    self.height = opts.height or (self.item_h * 5)
    self.vis_count = math.max(1, math.floor(self.height / self.item_h))
    -- Optional narrower highlight width; falls back to full column width.
    self.item_w = opts.item_w or self.width
    self.items = {}
    self.focused = 1
    self.offset = 0
    self.active = true -- false = suppress focused highlight
    self._rects = {} -- [i] = {x, y, w, h} for each visible item
    -- Mouse interaction tracking: don't engage hover until the mouse actually moves.
    self._mouse_interacted = false
    self._last_mx = -1
    self._last_my = -1
    self:setItems(items or {})
    return self
end

function List:setItems(items)
    self.items = items
    self.focused = math.min(self.focused, math.max(1, #items))
    self.offset = 0
    self:_clampOffset()
end

function List:getSelected()
    return self.items[self.focused]
end

function List:update(dt, inp)
    local n = #self.items
    if n == 0 then
        return
    end

    -- Keyboard / gamepad navigation
    if inp.device() ~= "mouse" then
        if inp.wasPressed("UP") then
            self.focused = self.focused - 1
            if self.focused < 1 then
                self.focused = n
            end
            self.active = true
            self:_clampOffset()
            if _G.sound then
                _G.sound.navigate()
            end
        end
        if inp.wasPressed("DOWN") then
            self.focused = self.focused + 1
            if self.focused > n then
                self.focused = 1
            end
            self.active = true
            self:_clampOffset()
            if _G.sound then
                _G.sound.navigate()
            end
        end
    end

    -- Mouse hover: set focus when over an item, clear when over none.
    -- Only engage mouse hover logic if the mouse has actually moved since
    -- the list was built — prevents gamescope's virtual pointer at boot
    -- from immediately clearing the keyboard focus highlight.
    if inp.device() == "mouse" and self._mouse_interacted then
        local mx, my = inp.mouseX(), inp.mouseY()
        local any_hit = false
        for idx, r in pairs(self._rects) do
            if hit(mx, my, r) then
                self.focused = idx
                self.active = true
                any_hit = true
                self:_clampOffset()
                break
            end
        end
        if not any_hit then
            self.active = false
        end
        if _G.cursor then
            _G.cursor.set(any_hit and "pointer" or "normal")
        end
    end

    -- Mark that the mouse has genuinely interacted once it moves.
    if
        inp.device() == "mouse" and (inp.mouseX() ~= self._last_mx or inp.mouseY() ~= self._last_my)
    then
        self._mouse_interacted = true
        self._last_mx = inp.mouseX()
        self._last_my = inp.mouseY()
    end

    if inp.wasPressed("SELECT") and self.active and self.on_select then
        if _G.sound then
            _G.sound.select()
        end
        self.on_select(self.items[self.focused])
    end
end

function List:draw()
    local x = self.x
    local y = self.y
    local w = self.width
    local ih = self.item_h
    local ah = self.arrow_h
    local font = self.font
    local items = self.items
    local n = #items

    local can_up = self.offset > 0
    local can_down = self.offset + self.vis_count < n

    love.graphics.setFont(font)

    -- ▲ arrow
    love.graphics.setColor(1, 1, 1, can_up and 0.5 or 0.0)
    love.graphics.printf("▲", x, y - ah, w, "center")

    self._rects = {}
    for i = 1, self.vis_count do
        local idx = self.offset + i
        if idx > n then
            break
        end
        local item = items[idx]
        local item_y = y + (i - 1) * ih
        local focused = (idx == self.focused) and self.active
        -- Hit/highlight rect is item_w wide, centred in the column — matches the bg highlight.
        local bg_x = x + math.floor((w - self.item_w) / 2)
        self._rects[idx] = { bg_x, item_y, self.item_w, ih }

        if focused then
            local bg_x = x + math.floor((w - self.item_w) / 2)
            love.graphics.setColor(T.ROW_FOCUS_BG)
            love.graphics.rectangle("fill", bg_x, item_y, self.item_w, ih, 4, 4)
        end

        love.graphics.setColor(focused and T.BTN_FOCUSED or T.BTN_NORMAL)
        local text_y = item_y + (ih - font:getHeight()) / 2
        love.graphics.printf(item.label, x, text_y, w, "center")
    end

    -- ▼ arrow
    love.graphics.setColor(1, 1, 1, can_down and 0.5 or 0.0)
    love.graphics.printf("▼", x, y + self.vis_count * ih, w, "center")

    love.graphics.setColor(1, 1, 1, 1)
end

function List:_clampOffset()
    local n = #self.items
    if n == 0 then
        self.offset = 0
        return
    end
    if self.focused > self.offset + self.vis_count then
        self.offset = self.focused - self.vis_count
    end
    if self.focused <= self.offset then
        self.offset = self.focused - 1
    end
    self.offset = math.max(0, math.min(self.offset, n - self.vis_count))
end

return List
