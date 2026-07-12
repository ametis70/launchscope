-- Icon system.
-- Supports three modes set via icons.init():
--   "pixel"   — loads pre-rasterised white PNG assets from assets/icons/.
--               Tinted at draw time via love.graphics.setColor so any colour
--               can be achieved: white image × colour = final colour.
--   "unicode" — Nerd Font codepoint strings; drawn as text at font_size.
--   "none"    — no icons; icon() returns "" and draw() is a no-op.
--
-- PNG images are white on transparent so any tint works correctly.
-- Nearest-neighbour filtering is applied for crisp pixel art rendering.
--
-- Public API:
--   icons.init(mode, size, font)        call once from _init()
--   icons.draw(name, x, y, r,g,b,a)    draw icon at position with colour
--   icons.width(name, font_override)    horizontal advance in pixels
--   icons.height(font_override)         icon height in pixels

local M = {}

-- ── Unicode codepoints (Nerd Font) ────────────────────────────────────── --
local UNICODE = {
    clock    = "󰥔 ",
    calendar = "󰃭 ",
    volume   = "󰕾 ",
    mute     = "󰖁 ",
    power    = "󰐥 ",
    settings = "󰒓 ",
    reload   = "󰑐 ",
    close    = "󰅙 ",
    back     = "󰁮 ",
    confirm  = "󰄬 ",
    cancel   = "󰅖 ",
    delete   = "󰆴 ",
    plus     = "󰐕 ",
    minus    = "󰍴 ",
}

-- ── PNG asset filenames ────────────────────────────────────────────────── --
local PNG_FILES = {
    clock    = "assets/icons/clock.png",
    calendar = "assets/icons/calendar.png",
    volume   = "assets/icons/volume.png",
    mute     = "assets/icons/mute.png",
    power    = "assets/icons/power.png",
    settings = "assets/icons/settings.png",
    reload   = "assets/icons/reload.png",
    close    = "assets/icons/close.png",
    back     = "assets/icons/back.png",
    confirm  = "assets/icons/confirm.png",
    cancel   = "assets/icons/cancel.png",
    delete   = "assets/icons/delete.png",
    plus     = "assets/icons/plus.png",
    minus    = "assets/icons/minus.png",
}

-- ── State ─────────────────────────────────────────────────────────────── --
local _mode  = "unicode"
local _size  = 32
local _font  = nil
local _cache = {}   -- [name] = love.Image (png mode)

-- ── PNG loader ────────────────────────────────────────────────────────── --

local function loadPNG(path)
    local ok, img = pcall(love.graphics.newImage, path)
    if not ok then
        print("WARNING icons: failed to load " .. path .. ": " .. tostring(img))
        return nil
    end
    -- Pixel art icons: nearest-neighbour keeps edges sharp at any scale.
    img:setFilter("nearest", "nearest")
    return img
end

-- ── Public API ────────────────────────────────────────────────────────── --

function M.init(mode, size, font)
    _mode  = mode or "unicode"
    _size  = size or 32
    _font  = font
    _cache = {}
end

-- draw renders the named icon at (x, y) with the given RGBA colour.
-- In png mode: draws a tinted white Image — colour acts as a multiply tint.
-- In unicode mode: draws the glyph string using the provided font.
-- Optional font_override: use a different font for unicode mode.
function M.draw(name, x, y, r, g, b, a, font_override)
    r, g, b, a = r or 1, g or 1, b or 1, a or 1

    if _mode == "none" then return 0 end

    if _mode == "pixel" then
        if _cache[name] == nil then
            local path = PNG_FILES[name]
            _cache[name] = path and loadPNG(path) or false
        end
        local img = _cache[name]
        if img then
            -- Scale the image to _size × _size at draw time.
            local iw, ih = img:getDimensions()
            local sx = _size / iw
            local sy = _size / ih
            love.graphics.setColor(r, g, b, a)
            love.graphics.draw(img, x, y, 0, sx, sy)
            love.graphics.setColor(1, 1, 1, 1)
            return _size
        end
        -- Fall through to unicode if PNG unavailable.
    end

    -- Unicode mode (or PNG fallback).
    local glyph = UNICODE[name]
    local font  = font_override or _font
    if not glyph or not font then return 0 end
    love.graphics.setFont(font)
    love.graphics.setColor(r, g, b, a)
    love.graphics.print(glyph, x, y)
    love.graphics.setColor(1, 1, 1, 1)
    return font:getWidth(glyph)
end

-- width returns the horizontal space the icon will occupy.
function M.width(name, font_override)
    if _mode == "none" then return 0 end
    if _mode == "pixel" then
        if _cache[name] == nil then
            local path = PNG_FILES[name]
            _cache[name] = path and loadPNG(path) or false
        end
        if _cache[name] then return _size end
    end
    local glyph = UNICODE[name]
    local font  = font_override or _font
    if not glyph or not font then return 0 end
    return font:getWidth(glyph)
end

-- height returns the icon height in pixels.
function M.height(font_override)
    if _mode == "pixel" then return _size end
    local font = font_override or _font
    if font then return font:getHeight() end
    return _size
end

return M
