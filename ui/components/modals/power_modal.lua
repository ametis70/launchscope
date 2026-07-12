-- Power menu modal.
-- Each item pushes a ConfirmModal before acting.
-- In standalone process mode an extra "Exit" item is shown instead of
-- "Restart Service" (which requires a running launchscoped daemon).
--
-- Usage:
--   _G.index.pushModal(PowerModal.new(_G.UI, { process_mode = cfg.process_mode }))

local BaseModal    = require("components.modals.base_modal")
local ConfirmModal = require("components.modals.confirm_modal")
local client       = require("lib.client")
local T            = require("lib.theme")
local hit          = require("lib.hittest")

local PowerModal = {}
PowerModal.__index = PowerModal

local BASE_ITEMS = {
    { id = "shutdown", label = "Shutdown" },
    { id = "suspend",  label = "Suspend"  },
    { id = "restart",  label = "Restart"  },
}

function PowerModal.new(ui, opts)
    local self       = setmetatable({}, PowerModal)
    self.ui          = ui
    self.focused     = 1
    self.font        = newFont(T.FONT_UI)
    self._rects      = {}
    self._standalone = opts and opts.process_mode == "standalone" or false
    self._server     = not self._standalone

    self._items = {}
    if self._standalone then
        self._items[#self._items+1] = { id = "quit",            label = "Exit"            }
    else
        self._items[#self._items+1] = { id = "restart_service", label = "Restart Service" }
    end
    for _, v in ipairs(BASE_ITEMS) do
        self._items[#self._items+1] = v
    end

    local n         = #self._items
    local content_w = math.floor(ui.font_size * 12)
    local content_h = n * ui.item_height + ui.padding
    self._modal     = BaseModal.new("Power", content_w, content_h, ui)
    return self
end

function PowerModal:update(inp)
    local consumed = self._modal:update(inp, function()
        _G.index.popModal()
    end)
    if consumed then return end

    local items = self._items
    local n     = #items

    -- Keyboard / gamepad navigation
    if inp.device() ~= "mouse" then
        if inp.wasPressed("UP") then
            self.focused = self.focused - 1
            if self.focused < 1 then self.focused = n end
            if _G.sound then _G.sound.navigate() end
        end
        if inp.wasPressed("DOWN") then
            self.focused = self.focused + 1
            if self.focused > n then self.focused = 1 end
            if _G.sound then _G.sound.navigate() end
        end
    end

    -- Mouse hover
    if inp.device() == "mouse" then
        local mx, my  = inp.mouseX(), inp.mouseY()
        local any_hit = false
        for i, r in ipairs(self._rects) do
            if hit(mx, my, r) then
                self.focused = i
                any_hit = true
                break
            end
        end
        if not any_hit then self.focused = 0 end
        if _G.cursor then
            if any_hit then
                _G.cursor.set("pointer")
            elseif not self._modal._header._focus_close then
                _G.cursor.set("normal")
            end
        end
    end

    if inp.wasPressed("SELECT") and self.focused >= 1 then
        if _G.sound then _G.sound.select() end
        local item = items[self.focused]
        self:_confirm(item)
    end
end

function PowerModal:_confirm(item)
    local messages = {
        restart_service = "Restart the launchscope service?",
        shutdown        = "Shut down the system?",
        suspend         = "Suspend the system?",
        restart         = "Restart the system?",
        quit            = "Close the launcher?",
    }
    local msg = messages[item.id] or (item.label .. "?")
    _G.index.pushModal(ConfirmModal.new(item.label, msg, function()
        if item.id == "quit" then
            love.event.quit()
        elseif item.id == "restart_service" then
            _G.index.popModal()   -- confirm
            _G.index.popModal()   -- power
            -- Restart the user service; the daemon will relaunch the UI.
            os.execute("systemctl --user restart launchscoped 2>/dev/null &")
        else
            _G.index.popModal()   -- confirm
            _G.index.popModal()   -- power
            client.power(item.id)
        end
    end, self.ui))
end

function PowerModal:draw()
    local sw, sh  = love.graphics.getDimensions()
    local font    = self.font
    local fh      = font:getHeight()
    local ih      = self.ui.item_height
    local items   = self._items

    local area = self._modal:drawBegin(sw, sh)

    self._rects = {}
    love.graphics.setFont(font)
    for i, item in ipairs(items) do
        local iy      = area.y + (i - 1) * ih
        local focused = (i == self.focused)
        self._rects[i] = { area.x, iy, area.w, ih }

        if focused then
            love.graphics.setColor(T.ROW_FOCUS_BG)
            love.graphics.rectangle("fill", area.x, iy, area.w, ih, 4, 4)
        end

        love.graphics.setColor(focused and T.BTN_FOCUSED or T.BTN_NORMAL)
        love.graphics.printf(item.label, area.px, iy + (ih - fh) / 2, area.pw, "center")
    end

    self._modal:drawEnd()
end

return PowerModal
