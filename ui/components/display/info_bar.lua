-- Info bar: top-left pill boxes [ time ] [ date ] [ vol% ]
-- Non-interactive display component.
-- Reads volume state from _G.volumeBar.

local pill = require("components.primitives.pill")
local T    = require("lib.theme")

local M = {}

local _ui        = nil
local _font      = nil
local _icon_font = nil
local _gap       = 0

function M.load(ui)
    _ui        = ui
    _font      = newFont(T.FONT_UI)
    -- Icons in the info bar use ui_icon_size (half the normal icon size).
    _icon_font = newFont(ui.ui_icon_size or T.FONT_UI)
    _gap       = math.floor(ui.font_size * 0.3)
end

function M.draw()
    if not _font or not _ui then return end

    local x = _ui.corner_padding
    local y = _ui.corner_padding

    local time_str = os.date("%H:%M")
    local date_str = os.date("%a %d %b %Y")
    local muted    = _G.volumeBar.getMuted()
    local pct      = math.floor(_G.volumeBar.getVolume() * 100 + 0.5)
    local vol_icon = muted and "mute" or "volume"
    local vol_col  = muted and T.TEXT_MUTED or T.TEXT

    local pill_h = math.floor(_ui.font_size * 1.4)
    x = x + pill.draw("clock",    time_str,   T.TEXT,   x, y, _ui, _font, _icon_font, pill_h) + _gap
    x = x + pill.draw("calendar", date_str,   T.TEXT,   x, y, _ui, _font, _icon_font, pill_h) + _gap
            pill.draw(vol_icon,   pct .. "%",  vol_col,  x, y, _ui, _font, _icon_font, pill_h)
end

return M
