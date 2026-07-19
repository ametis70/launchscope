-- Gamescope session configuration.
-- Shared by both the launcher display config and per-app launch config.
--
-- Schema (all fields optional):
--   enabled        bool     wrap in gamescope (default true for apps; N/A for launcher)
--   fullscreen     bool     -f flag (default true)
--   output         table    { width, height, refresh }  →  -W -H -r
--   inner          table    { width, height }            →  -w -h  (defaults to output)
--   filter         string   upscaler filter: "linear" | "nearest" | "fsr" | "nis" | "pixel"
--                           →  -F <filter>  (also sets -S fit when inner != output)
--   scaler         string   scaler type: "auto" | "integer" | "fit" | "fill" | "stretch"
--                           →  -S <scaler>  (default "fit" when filter is set)
--   sharpness      int      0 (max) – 20 (min)  →  --sharpness N
--   hdr            bool     →  --hdr-enabled
--   adaptive_sync  bool     →  --adaptive-sync
--   force_grab     bool     →  --force-grab-cursor
--   expose_wayland bool     →  --expose-wayland
--   composite_debug bool    →  --composite-debug
--   mangoapp       bool     →  --mangoapp
--   extra_flags    [string] verbatim flags before --

local M = {}

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

-- Build a gamescope argv string from a gamescope config table.
-- If exec is provided, appends " -- <exec>" at the end.
function M.buildArgv(gs, exec)
    gs = gs or {}

    local out = gs.output or {}
    local inn = gs.inner or {}
    local ow = out.width or 1920
    local oh = out.height or 1080
    local orr = out.refresh or 60
    local iw = inn.width or ow
    local ih = inn.height or oh

    local parts = { "gamescope" }

    if gs.fullscreen ~= false then
        parts[#parts + 1] = "-f"
    end

    parts[#parts + 1] = "-W"
    parts[#parts + 1] = tostring(ow)
    parts[#parts + 1] = "-H"
    parts[#parts + 1] = tostring(oh)
    parts[#parts + 1] = "-w"
    parts[#parts + 1] = tostring(iw)
    parts[#parts + 1] = "-h"
    parts[#parts + 1] = tostring(ih)
    parts[#parts + 1] = "-r"
    parts[#parts + 1] = tostring(orr)

    -- Upscaler filter (-F) and scaler (-S).
    -- Only emit when inner != output (otherwise no upscaling is needed).
    local has_inner = (iw ~= ow or ih ~= oh)
    local filter = gs.filter
    if filter then
        local scaler = gs.scaler or (has_inner and "fit" or "auto")
        parts[#parts + 1] = "-S"
        parts[#parts + 1] = scaler
        parts[#parts + 1] = "-F"
        parts[#parts + 1] = filter
    end

    if gs.sharpness then
        parts[#parts + 1] = "--sharpness"
        parts[#parts + 1] = tostring(gs.sharpness)
    end

    if gs.hdr then
        parts[#parts + 1] = "--hdr-enabled"
    end
    if gs.adaptive_sync then
        parts[#parts + 1] = "--adaptive-sync"
    end
    if gs.force_grab then
        parts[#parts + 1] = "--force-grab-cursor"
    end
    if gs.expose_wayland then
        parts[#parts + 1] = "--expose-wayland"
    end
    if gs.composite_debug then
        parts[#parts + 1] = "--composite-debug"
    end
    if gs.mangoapp then
        parts[#parts + 1] = "--mangoapp"
    end

    for _, flag in ipairs(gs.extra_flags or {}) do
        parts[#parts + 1] = shellQuote(flag)
    end

    if exec then
        parts[#parts + 1] = "--"
        parts[#parts + 1] = exec
    end

    return table.concat(parts, " ")
end

M.DEFAULTS = {
    fullscreen = true,
    output = { width = 1920, height = 1080, refresh = 60 },
    inner = nil,
    filter = nil,
    scaler = nil,
    sharpness = nil,
    hdr = false,
    adaptive_sync = false,
    force_grab = false,
    expose_wayland = false,
    composite_debug = false,
    mangoapp = false,
    extra_flags = {},
}

return M
