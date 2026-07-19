-- Base modal chrome.
-- Provides: full-screen dim overlay, rounded panel, Header component.
--
-- The close button is rendered and interactive only in mouse mode.
-- BACK (any device) calls on_close.
--
-- Constructor:
--   BaseModal.new(title, content_w, content_h, ui)
--     content_w / content_h: size of the area *inside* the panel (below the header).
--     The panel height is auto-computed: Header.height(ui) + content_h + padding * 2.
--
-- update(inp, on_close) → consumed bool
-- drawBegin(sw, sh)     → area {x,y,w,h, px,py,pw,ph, header_h}
-- drawEnd()
-- BaseModal.headerHeight(ui) → number   (static helper, delegates to Header)

local Header = require("components.primitives.header")
local T = require("lib.theme")

local M = {}
M.__index = M

function M.new(title, content_w, content_h, ui)
    local self = setmetatable({}, M)
    self.content_w = content_w
    self.content_h = content_h
    self.ui = ui
    self._header = Header.new(title, ui)
    return self
end

-- Static helper — panel consumers need this to size their content_h correctly.
function M.headerHeight(ui)
    return Header.height(ui)
end

function M:update(inp_layer, on_close)
    return self._header:update(inp_layer, on_close)
end

function M:drawBegin(sw, sh)
    local ui = self.ui
    local pad = ui.padding
    local hdr_h = Header.height(ui)
    local pw = self.content_w + pad * 2
    local ph = hdr_h + self.content_h + pad * 2
    local px = math.floor((sw - pw) / 2)
    local py = math.floor((sh - ph) / 2)

    -- Panel (no overlay here — stack.draw() handles the single overlay)
    love.graphics.setColor(T.PANEL)
    love.graphics.rectangle("fill", px, py, pw, ph, 8, 8)

    -- Header (title + close button + separator)
    self._header:draw(px, py, pw)

    love.graphics.setColor(1, 1, 1, 1)

    return {
        x = px + pad,
        y = py + hdr_h + pad,
        w = self.content_w,
        h = self.content_h,
        px = px,
        py = py,
        pw = pw,
        ph = ph,
        header_h = hdr_h,
    }
end

function M:drawEnd()
    love.graphics.setColor(1, 1, 1, 1)
end

return M
