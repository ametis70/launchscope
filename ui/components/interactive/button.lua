-- Icon+label pill button.
-- Self-contained: owns its position and rect, handles mouse hover and click.
--
-- Usage:
--   local Button = require("components.interactive.button")
--   local btn = Button.new({ icon="power", label="Power", ui=_G.UI })
--   btn:setPos(x, y)
--   btn.on_select = function() ... end
--   btn:update(inp)   -- call each frame
--   btn:draw()
--   btn:width()       -- measure pill width without drawing

local icons = require("lib.icons")
local T     = require("lib.theme")
local hit   = require("lib.hittest")

local Button = {}
Button.__index = Button

function Button.new(opts)
    local self       = setmetatable({}, Button)
    self.icon        = opts.icon  or ""
    self.label       = opts.label or ""
    self.ui          = opts.ui
    self.on_select   = opts.on_select or nil
    self.focused     = false
    self._rect       = { 0, 0, 0, 0 }
    self._font       = newFont(T.FONT_UI)
    -- Smaller icon font for aux buttons (uses ui_icon_size if available).
    local isz        = opts.ui.ui_icon_size or T.FONT_UI
    self._icon_font  = newFont(isz)
    return self
end

function Button:setPos(x, y)
    self._rect[1] = x
    self._rect[2] = y
    self._rect[3] = self:width()
    self._rect[4] = self:height()
end

function Button:width()
    local ui    = self.ui
    local pad_x = math.floor(ui.font_size * 0.6)
    local iw    = icons.width(self.icon, self._icon_font)
    local isep  = iw > 0 and math.floor(ui.font_size * 0.25) + 4 or 0
    return pad_x + iw + isep + self._font:getWidth(self.label) + pad_x
end

function Button:height()
    local ui = self.ui
    -- Height proportional to font size so scaled variants grow correctly.
    return math.floor(ui.font_size * 1.4)
end

function Button:rect()
    return self._rect
end

-- update: handles mouse hover and SELECT.
-- inp: the input module (or any table with wasPressed / mouseX / mouseY / device)
function Button:update(inp)
    -- Mouse hover
    if inp.device() == "mouse" then
        local mx, my = inp.mouseX(), inp.mouseY()
        self.focused = hit(mx, my, self._rect)
        if _G.cursor then
            _G.cursor.set(self.focused and "pointer" or "normal")
        end
        -- Mouse click is handled here; keyboard/gamepad SELECT is handled by the caller.
        if self.focused and inp.wasPressed("SELECT") then
            if self.on_select then self.on_select() end
        end
    end
end

function Button:draw()
    local ui    = self.ui
    local x, y  = self._rect[1], self._rect[2]
    local w, bh = self:width(), self:height()
    local pad_x = math.floor(ui.font_size * 0.6)
    local r     = math.floor(ui.font_size * 0.2)
    local ih    = icons.height(self._icon_font)
    local fh    = self._font:getHeight()
    local iw    = icons.width(self.icon, self._icon_font)
    local isep  = iw > 0 and math.floor(ui.font_size * 0.25) + 4 or 0
    local col   = self.focused and T.BTN_FOCUSED or T.BTN_NORMAL

    -- Background: dimmer when unfocused, no outline ever
    local bg_col = self.focused and T.BTN_BG or { 1, 1, 1, 0.04 }
    love.graphics.setColor(bg_col)
    love.graphics.rectangle("fill", x, y, w, bh, r, r)

    -- Icon and text both centred vertically in bh
    local ix = x + pad_x
    local iy = y + math.floor((bh - ih) / 2)
    icons.draw(self.icon, ix, iy, col[1], col[2], col[3], col[4] or 1, self._icon_font)

    local tx = ix + iw + isep
    local ty = y + math.floor((bh - fh) / 2)
    love.graphics.setFont(self._font)
    love.graphics.setColor(col)
    love.graphics.print(self.label, tx, ty)

    love.graphics.setColor(1, 1, 1, 1)
end

return Button
