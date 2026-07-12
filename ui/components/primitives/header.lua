-- Panel header component.
-- One canonical implementation of the title bar used by every panel and modal.
-- Renders: title (left) + close icon (right, always visible).
-- Close icon is clickable with the mouse; BACK works on all devices.
-- Draws a separator line at the bottom of the header.
--
-- Usage:
--   local Header = require("components.primitives.header")
--   local hdr = Header.new(title, ui)
--
--   -- Each frame in update:
--   local closed = hdr:update(inp, on_close)
--   -- closed = true if BACK was pressed or the close button was clicked.
--   -- on_close is called immediately; the return value lets callers guard
--   -- further logic in the same frame.
--
--   -- In draw, given the panel rect (px, py, pw):
--   local bottom_y = hdr:draw(px, py, pw)
--   -- bottom_y = py + header height; start drawing content below this.
--
--   -- Static helpers:
--   Header.height(ui)   → pixel height of the header bar

local T   = require("lib.theme")
local hit = require("lib.hittest")

local Header = {}
Header.__index = Header

local function _icons()
    local ok, m = pcall(require, "lib.icons")
    return ok and m or nil
end

-- height: static helper — same formula used everywhere.
function Header.height(ui)
    local f = newFont(T.FONT_UI)
    return f:getHeight() + ui.padding * 2
end

function Header.new(title, ui)
    local self        = setmetatable({}, Header)
    self.title        = title
    self.ui           = ui
    self.font         = newFont(T.FONT_UI)
    self._close_rect  = nil
    self._focus_close = false
    return self
end

-- update: process BACK and close-button click.
-- on_close is called when the user wants to dismiss the panel.
-- Returns true if the event was consumed.
function Header:update(inp, on_close)
    if inp.wasPressed("BACK") then
        if _G.sound then _G.sound.select() end
        if on_close then on_close() end
        return true
    end

    if inp.device() ~= "mouse" then
        self._focus_close = false
        return false
    end

    if self._close_rect then
        local mx, my = inp.mouseX(), inp.mouseY()
        self._focus_close = hit(mx, my, self._close_rect)
        if _G.cursor then
            _G.cursor.set(self._focus_close and "pointer" or "normal")
        end
        if self._focus_close and inp.wasPressed("SELECT") then
            if _G.sound then _G.sound.select() end
            if on_close then on_close() end
            return true
        end
    end

    return false
end

-- draw: render the header inside the panel.
-- px, py: panel top-left corner.
-- pw:     panel width.
-- Returns the y coordinate directly below the separator line
-- (i.e. where content should begin).
function Header:draw(px, py, pw)
    local ui  = self.ui
    local pad = ui.padding
    local fh  = self.font:getHeight()
    local hh  = fh + pad * 2   -- header height

    -- Title
    love.graphics.setFont(self.font)
    love.graphics.setColor(T.MODAL_TITLE)
    love.graphics.print(self.title, px + pad, py + pad)

    -- Close icon: always rendered, dimmed normally, full white on hover.
    local ic     = _icons()
    local icon_w = ic and ic.width("close") or 0
    if icon_w > 0 then
        local cx = px + pw - icon_w - pad
        local cy = py + math.floor((hh - ic.height()) / 2)
        self._close_rect = { cx - pad * 0.5, py, icon_w + pad, hh }
        local col = self._focus_close and T.CLOSE_FOCUSED or T.CLOSE_NORMAL
        ic.draw("close", cx, cy, col[1], col[2], col[3], col[4] or 1)
    else
        self._close_rect = nil
    end

    -- Separator line
    love.graphics.setColor(T.PANEL_BORDER)
    love.graphics.rectangle("fill", px, py + hh, pw, 1)

    love.graphics.setColor(1, 1, 1, 1)
    return py + hh   -- bottom of header (separator line y)
end

return Header
