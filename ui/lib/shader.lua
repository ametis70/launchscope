-- Background renderer.
-- Supports two modes set via background.type in config.json:
--
--   "shader"  — animated GLSL shader (default)
--               background.animate = false freezes the shader at t=0
--   "solid"   — flat colour, no shader
--               background.color   = "#rrggbb" hex string
--
-- Public API:
--   M.load(bg_cfg)         call once from _init()
--   M.applyConfig(bg_cfg)  call on resize or config change
--   M.update(dt)           advance shader time (no-op for solid / animate=false)
--   M.draw()               draw the background

local M = {}

local _shader = nil
local _t = 0
local _animate = true
local _type = "shader"
local _color = { 0, 0, 0, 1 } -- solid fallback

-- Parse "#rrggbb" or "#rrggbbaa" → { r, g, b, a } in 0–1 range.
local function parseHex(hex)
    if not hex then
        return { 0, 0, 0, 1 }
    end
    hex = hex:gsub("^#", "")
    local r = tonumber(hex:sub(1, 2), 16) or 0
    local g = tonumber(hex:sub(3, 4), 16) or 0
    local b = tonumber(hex:sub(5, 6), 16) or 0
    local a = hex:len() >= 8 and (tonumber(hex:sub(7, 8), 16) or 255) or 255
    return { r / 255, g / 255, b / 255, a / 255 }
end

function M.load(bg_cfg)
    M.applyConfig(bg_cfg)
    if _type == "shader" and not _shader then
        local ok, s = pcall(love.graphics.newShader, "assets/shaders/background.glsl")
        if ok then
            _shader = s
            M._sendResolution()
        else
            print("WARNING background: shader failed to compile: " .. tostring(s))
            _type = "solid"
        end
    end
end

function M.applyConfig(bg_cfg)
    local cfg = bg_cfg or {}
    _type = cfg.type or "shader"
    _animate = cfg.animate ~= false -- default true
    _color = parseHex(cfg.color or "#0d1440")

    if _shader then
        M._sendResolution()
    end
end

function M._sendResolution()
    if not _shader then
        return
    end
    local sw, sh = love.graphics.getDimensions()
    _shader:send("u_resolution", { sw, sh })
end

function M.update(dt)
    if _type ~= "shader" or not _animate then
        return
    end
    _t = _t + dt
    if _shader then
        _shader:send("u_time", _t)
    end
end

function M.draw()
    if _type == "solid" then
        love.graphics.setShader()
        love.graphics.setColor(_color)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    -- Shader mode.
    if not _shader then
        -- Fallback: black background.
        love.graphics.setColor(0, 0, 0, 1)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
        love.graphics.setColor(1, 1, 1, 1)
        return
    end

    love.graphics.setShader(_shader)
    love.graphics.setColor(1, 1, 1, 1)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getDimensions())
    love.graphics.setShader()
end

return M
