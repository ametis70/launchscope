-- Pill primitive.
-- Stateless renderer: background rect + optional icon + text label.
-- Returns the pill width so callers can advance their x cursor.
--
-- Usage:
--   local pill = require("components.primitives.pill")
--   local w = pill.draw(icon_name, label, color, x, y, ui, font, icon_font, min_h)
--
-- icon_font: optional love.Font for icon rendering (unicode mode).
-- min_h:     optional minimum pill height in pixels.

local icons = require("lib.icons")
local T     = require("lib.theme")

local M = {}

function M.draw(icon_name, label, color, x, y, ui, font, icon_font, min_h)
    font = font or love.graphics.getFont()

    local fh  = font:getHeight()
    local ih  = icons.height(icon_font)
    -- Pill height: at least min_h, at least enough to hold the text with padding.
    local pad  = math.floor(ui.font_size * 0.2)
    local h    = math.max(min_h or 0, fh + pad * 2)

    local iw  = icons.width(icon_name, icon_font)
    local sep = (iw > 0) and math.floor(ui.font_size * 0.2) + 4 or 0
    local tw  = font:getWidth(label)
    local pad_h = T.ROW_PAD_H
    local w   = pad_h + iw + sep + tw + pad_h

    local radius = math.floor(ui.font_size * 0.25)

    -- Background
    love.graphics.setColor(T.PILL_BG)
    love.graphics.rectangle("fill", x, y, w, h, radius, radius)

    -- Icon (vertically centred in pill)
    local ix = x + pad_h
    local iy = y + math.floor((h - ih) / 2)
    icons.draw(icon_name, ix, iy, color[1], color[2], color[3], color[4] or 1, icon_font)

    -- Label (vertically centred in pill)
    local tx = ix + iw + sep
    local ty = y + math.floor((h - fh) / 2)
    love.graphics.setFont(font)
    love.graphics.setColor(color)
    love.graphics.print(label, tx, ty)

    love.graphics.setColor(1, 1, 1, 1)
    return w
end

-- height returns the pill height for a given font and ui, matching draw().
function M.height(ui, font)
    local fh = font and font:getHeight() or 0
    return fh + math.floor(ui.font_size * 0.4)
end

return M
