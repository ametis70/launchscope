-- Confirmation modal.
-- Two-button No/Yes dialog (No on left, Yes on right). Pushed onto the modal stack.
--
-- Usage:
--   local ConfirmModal = require("components.modals.confirm_modal")
--   _G.index.pushModal(ConfirmModal.new(title, message, on_confirm, ui))
--
-- on_confirm() is called only when the user selects "Yes".
-- Cancelling (No, BACK, close icon) pops without calling on_confirm.

local BaseModal = require("components.modals.base_modal")
local T = require("lib.theme")
local hit = require("lib.hittest")

local ConfirmModal = {}
ConfirmModal.__index = ConfirmModal

-- No on left (index 1), Yes on right (index 2).
local OPTIONS = { { id = "no", label = "No" }, { id = "yes", label = "Yes" } }

function ConfirmModal.new(title, message, on_confirm, ui)
    local self = setmetatable({}, ConfirmModal)
    self.ui = ui
    self.message = message
    self.on_confirm = on_confirm
    self.focused = 1 -- default: No
    self.font = newFont(T.FONT_UI)
    self.font_msg = newFont(T.FONT_UI)
    self._rects = {}

    local content_w = math.floor(love.graphics.getWidth() * 0.4)
    local msg_h = self.font_msg:getHeight() * 2 + ui.padding
    local content_h = msg_h + ui.padding + ui.item_height
    self._modal = BaseModal.new(title, content_w, content_h, ui)
    return self
end

function ConfirmModal:_close(confirm)
    _G.index.popModal()
    if confirm and self.on_confirm then
        self.on_confirm()
    end
end

function ConfirmModal:update(inp)
    local consumed = self._modal:update(inp, function()
        self:_close(false)
    end)
    if consumed then
        return
    end

    local dev = inp.device()

    if dev == "mouse" then
        local mx, my = inp.mouseX(), inp.mouseY()
        local any_hit = false
        for i, r in ipairs(self._rects) do
            if hit(mx, my, r) then
                self.focused = i
                any_hit = true
                if inp.wasPressed("SELECT") then
                    self:_close(OPTIONS[i].id == "yes")
                end
                break
            end
        end
        if _G.cursor then
            if any_hit then
                _G.cursor.set("pointer")
            elseif not self._modal._header._focus_close then
                _G.cursor.set("normal")
            end
        end
        return
    end

    if inp.wasPressed("LEFT") or inp.wasPressed("RIGHT") then
        self.focused = self.focused == 1 and 2 or 1
    elseif inp.wasPressed("SELECT") then
        self:_close(OPTIONS[self.focused].id == "yes")
    end
end

function ConfirmModal:draw()
    local sw, sh = love.graphics.getDimensions()
    local ui = self.ui
    local area = self._modal:drawBegin(sw, sh)

    -- Message — centred vertically in the space above the buttons
    local btn_h = ui.item_height
    local space_above = area.h - ui.padding - btn_h
    local msg_y = area.y + math.floor((space_above - self.font_msg:getHeight()) / 2)
    love.graphics.setFont(self.font_msg)
    love.graphics.setColor(T.TEXT)
    love.graphics.printf(self.message, area.x, msg_y, area.w, "center")

    -- No / Yes buttons side by side
    local btn_w = math.floor(area.w * 0.35)
    local gap = math.floor(area.w * 0.1)
    local total_w = btn_w * 2 + gap
    local btn_y = area.y + area.h - btn_h
    local start_x = area.x + math.floor((area.w - total_w) / 2)

    self._rects = {}
    for i, opt in ipairs(OPTIONS) do
        local bx = start_x + (i - 1) * (btn_w + gap)
        local focused = (i == self.focused)
        self._rects[i] = { bx, btn_y, btn_w, btn_h }

        -- Background only when focused, no outline
        love.graphics.setColor(focused and T.BTN_BG or { 0, 0, 0, 0 })
        love.graphics.rectangle("fill", bx, btn_y, btn_w, btn_h, 6, 6)

        -- Label
        love.graphics.setFont(self.font)
        love.graphics.setColor(focused and T.BTN_FOCUSED or T.BTN_NORMAL)
        love.graphics.printf(
            opt.label,
            bx,
            btn_y + (btn_h - self.font:getHeight()) / 2,
            btn_w,
            "center"
        )
    end

    self._modal:drawEnd()
end

return ConfirmModal
