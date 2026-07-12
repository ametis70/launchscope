-- UI configuration loader.
-- Reads $XDG_CONFIG_HOME/launchscope/config.json and
-- $XDG_CONFIG_HOME/launchscope/config.override.json directly from disk.
-- The override file is deep-merged on top of the base with higher priority.
--
-- The UI config is completely independent of the server (launchscoped).
-- The server only knows about API settings and apps — not fonts, scale, etc.
--
-- Schema (all fields optional; defaults applied for missing ones):
--
--   session_mode      string   How the launcher session itself is run:
--                              "drm_gamescope"    — gamescope owns the display via KMS/DRM
--                              "nested_gamescope" — gamescope runs inside an existing compositor
--                              "nested_direct"    — love runs directly inside an existing compositor
--                              (default: "drm_gamescope")
--
--   process_mode      string   Who manages app processes:
--                              "daemon"     — delegates to launchscoped over HTTP
--                              "standalone" — manages processes directly, no daemon needed
--                              (default: "daemon")
--
--   display.fullscreen bool    Whether to run fullscreen. Only meaningful in
--                              "nested_gamescope" and "nested_direct" session modes.
--                              Ignored in "drm_gamescope" (always fullscreen).
--                              (default: true)
--
--   font            string   font name (resolved via fc-match) or absolute path
--   icons           string   "pixel" | "unicode" | "none"  (default: "pixel")
--   icon_size       number   Size in px for icons (default: matches ui_icon_size)
--   scale           number   0.5 – 3.0  (default: 1.0)
--   display         table    Gamescope session config for the launcher window.
--                            Same schema as app gamescope (minus 'enabled'):
--                              fullscreen, output, inner, filter, scaler,
--                              sharpness, hdr, adaptive_sync, force_grab,
--                              expose_wayland, composite_debug, mangoapp, extra_flags
--   background      table    { type, animate, color }
--   idle            table    { dim_timeout, blank_timeout, blank_mode, blank_off, blank_on }
--                            dim_timeout: seconds before dimming (default: 60, 0 = disabled)
--                            blank_timeout: seconds before blanking (default: 0 = disabled)
--                            blank_mode: "wlopm" (default) or "cec" (daemon mode only)
--                            cec_activate_on_start: send CEC activate on UI startup (default: true, cec+daemon only)
--                            blank_off: shell command to turn display off (blank_mode = "wlopm" only)
--                            blank_on:  shell command to turn display on  (blank_mode = "wlopm" only)

local json = require("lib.json")

local M = {}

-- ── Defaults ──────────────────────────────────────────────────────────── --

local DEFAULTS = {
    session_mode    = "drm_gamescope",
    process_mode    = "daemon",
    ui_volume       = 0.5,
    font      = nil,
    icons     = "pixel",
    icon_size = nil,
    scale     = 1.0,
    display   = {
        fullscreen = true,
        output     = { width = 1920, height = 1080, refresh = 60 },
        inner      = nil,
    },
    background = {
        type    = "shader",
        animate = true,
        color   = "#0d1440",
    },
    idle = {
        dim_timeout           = 60,       -- 1 minute; 0 = disabled
        blank_timeout         = 0,        -- disabled by default; user must opt in
        blank_mode            = "wlopm",  -- "wlopm" or "cec"
        cec_activate_on_start = true,     -- send CEC activate on startup (cec+daemon only)
        blank_off             = nil,      -- nil = use wlopm default
        blank_on              = nil,      -- nil = use wlopm default
    },
}

-- ── Config directory ──────────────────────────────────────────────────── --

local function configDir()
    local xdg = os.getenv("XDG_CONFIG_HOME")
    if xdg and xdg ~= "" then
        return xdg .. "/launchscope"
    end
    local home = os.getenv("HOME") or ""
    return home .. "/.config/launchscope"
end

-- ── JSON helpers ──────────────────────────────────────────────────────── --

local function readJSON(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local raw = fh:read("*a")
    fh:close()
    local ok, data = pcall(json.decode, raw)
    if not ok then
        print("WARNING: failed to parse " .. path .. ": " .. tostring(data))
        return nil
    end
    return data
end

local function writeJSON(path, data)
    local ok, encoded = pcall(json.encode, data)
    if not ok then
        return false, "JSON encode error: " .. tostring(encoded)
    end
    local fh = io.open(path .. ".tmp", "w")
    if not fh then
        return false, "cannot open " .. path .. ".tmp for writing"
    end
    fh:write(encoded)
    fh:close()
    local ok2 = os.rename(path .. ".tmp", path)
    if not ok2 then
        return false, "cannot rename tmp file to " .. path
    end
    return true, nil
end

-- ── Deep merge ────────────────────────────────────────────────────────── --
-- Returns a new table with all keys from base, overridden by override.

local function deepMerge(base, override)
    local result = {}
    for k, v in pairs(base) do
        result[k] = v
    end
    for k, v in pairs(override) do
        if type(v) == "table" and type(result[k]) == "table" then
            result[k] = deepMerge(result[k], v)
        else
            result[k] = v
        end
    end
    return result
end

-- ── Apply defaults ────────────────────────────────────────────────────── --

local function applyDefaults(cfg)
    return deepMerge(DEFAULTS, cfg or {})
end

-- ── Public API ────────────────────────────────────────────────────────── --

-- Load reads config.json + config.override.json from the launchscope config
-- directory, merges them, applies defaults, and returns the result.
-- The LAUNCHSCOPE_FONT env var overrides cfg.font if set (dev/override use).
function M.load()
    local dir  = configDir()
    local base = readJSON(dir .. "/config.json") or {}
    local over = readJSON(dir .. "/config.override.json") or {}
    local cfg  = applyDefaults(deepMerge(base, over))

    -- Normalise legacy icon mode values → "pixel".
    if cfg.icons == true    then cfg.icons = "unicode" end
    if cfg.icons == false   then cfg.icons = "none"    end
    if cfg.icons == "svg"   then cfg.icons = "pixel"   end
    if cfg.icons == "png"   then cfg.icons = "pixel"   end

    -- Env var overrides (highest priority — set by wrapper script or operator).
    local session_env = os.getenv("LAUNCHSCOPE_SESSION_MODE")
    if session_env and session_env ~= "" then
        cfg.session_mode = session_env
    end

    local process_env = os.getenv("LAUNCHSCOPE_PROCESS_MODE")
    if process_env and process_env ~= "" then
        cfg.process_mode = process_env
    end

    local font_env = os.getenv("LAUNCHSCOPE_FONT")
    if font_env and font_env ~= "" then
        cfg.font = font_env
    end

    return cfg
end

-- Save writes the given config table to config.json (or config.override.json
-- when the base file is a symlink, i.e. Nix-managed).
-- Returns true on success, or false + error string on failure.
function M.save(cfg)
    local dir      = configDir()
    local basePath = dir .. "/config.json"

    -- Detect if base is a symlink (Nix-managed) — write to override instead.
    local path = basePath
    local fh = io.open(basePath, "r")
    if fh then fh:close() end
    -- io doesn't expose lstat; use a heuristic: try to open for writing.
    -- If it fails but reading succeeded, it's likely read-only (Nix store).
    local writable = io.open(basePath, "a")
    if writable then
        writable:close()
    else
        path = dir .. "/config.override.json"
    end

    return writeJSON(path, cfg)
end

-- ConfigDir returns the launchscope config directory path.
function M.configDir()
    return configDir()
end

return M
