#!/usr/bin/env lua
-- gamescope-args.lua
-- Reads ~/.config/launchscope/config.json (+ override) and prints the
-- gamescope argv needed to wrap the Launchscope UI, based on session_mode.
--
-- Also prints "export LAUNCHSCOPE_SESSION_MODE=<value>" so the shell wrapper
-- can pass the session mode into love via env var (used by conf.lua).
--
-- Usage (from the shell wrapper):
--   eval $(lua gamescope-args.lua)
--   exec ${GS_ARGS:+$GS_ARGS --} love /path/to/launchscope.love
--
-- session_mode behaviour:
--   drm_gamescope    — prints gamescope argv (DRM/KMS backend, fullscreen)
--   nested_gamescope — prints gamescope argv (nested inside compositor)
--   nested_direct    — prints nothing; love runs directly in the compositor
--
-- In all cases, exports LAUNCHSCOPE_SESSION_MODE for conf.lua.
-- Exit code 0 always.

-- ── Minimal JSON parser ───────────────────────────────────────────────────

local function readFile(path)
    local fh = io.open(path, "r")
    if not fh then return nil end
    local s = fh:read("*a"); fh:close()
    return s
end

local json = (function()
    local function skipWS(s, i)
        while i <= #s and s:sub(i,i):match("%s") do i = i + 1 end
        return i
    end
    local parseValue
    local function parseString(s, i)
        assert(s:sub(i,i) == '"')
        i = i + 1
        local buf = {}
        while i <= #s do
            local c = s:sub(i,i)
            if c == '"' then return table.concat(buf), i + 1 end
            if c == '\\' then
                i = i + 1; c = s:sub(i,i)
                local esc = {['"']='"',['\\']='\\',['/']='\x2F',['n']='\n',['r']='\r',['t']='\t',['b']='\b',['f']='\f'}
                buf[#buf+1] = esc[c] or c
            else
                buf[#buf+1] = c
            end
            i = i + 1
        end
        error("unterminated string")
    end
    local function parseNumber(s, i)
        local num, j = s:match("^(-?%d+%.?%d*[eE]?[+-]?%d*)()", i)
        return tonumber(num), j
    end
    local function parseArray(s, i)
        assert(s:sub(i,i) == '['); i = i + 1
        local arr = {}
        i = skipWS(s, i)
        if s:sub(i,i) == ']' then return arr, i + 1 end
        while true do
            local v; v, i = parseValue(s, i)
            arr[#arr+1] = v
            i = skipWS(s, i)
            if s:sub(i,i) == ']' then return arr, i + 1 end
            assert(s:sub(i,i) == ',', "expected ,"); i = i + 1
            i = skipWS(s, i)
        end
    end
    local function parseObject(s, i)
        assert(s:sub(i,i) == '{'); i = i + 1
        local obj = {}
        i = skipWS(s, i)
        if s:sub(i,i) == '}' then return obj, i + 1 end
        while true do
            i = skipWS(s, i)
            local k; k, i = parseString(s, i)
            i = skipWS(s, i)
            assert(s:sub(i,i) == ':', "expected :"); i = i + 1
            i = skipWS(s, i)
            local v; v, i = parseValue(s, i)
            obj[k] = v
            i = skipWS(s, i)
            if s:sub(i,i) == '}' then return obj, i + 1 end
            assert(s:sub(i,i) == ',', "expected ,"); i = i + 1
        end
    end
    parseValue = function(s, i)
        i = skipWS(s, i)
        local c = s:sub(i,i)
        if c == '"' then return parseString(s, i)
        elseif c == '{' then return parseObject(s, i)
        elseif c == '[' then return parseArray(s, i)
        elseif c == 't' then assert(s:sub(i,i+3)=="true");  return true,  i+4
        elseif c == 'f' then assert(s:sub(i,i+4)=="false"); return false, i+5
        elseif c == 'n' then assert(s:sub(i,i+3)=="null");  return nil,   i+4
        else return parseNumber(s, i) end
    end
    return {
        decode = function(s)
            local ok, v = pcall(parseValue, s, skipWS(s, 1))
            return ok and v or nil
        end
    }
end)()

-- ── Config loading ────────────────────────────────────────────────────────

local function deepMerge(base, over)
    local r = {}
    for k, v in pairs(base) do r[k] = v end
    for k, v in pairs(over) do
        if type(v) == "table" and type(r[k]) == "table" then
            r[k] = deepMerge(r[k], v)
        else
            r[k] = v
        end
    end
    return r
end

local cfgDir   = (os.getenv("XDG_CONFIG_HOME") or (os.getenv("HOME") .. "/.config")) .. "/launchscope"
local base_raw = readFile(cfgDir .. "/config.json")
local over_raw = readFile(cfgDir .. "/config.override.json")

local base = json.decode(base_raw or "{}")
local over = json.decode(over_raw or "{}")

if not base then
    io.stderr:write("gamescope-args: ERROR: failed to parse " .. cfgDir .. "/config.json\n")
    os.exit(1)
end
over = over or {}

local cfg     = deepMerge(base, over)
local session = cfg.session_mode or "drm_gamescope"
local gs      = cfg.display or {}

-- Always export the session mode so conf.lua knows what window to open.
io.write("export LAUNCHSCOPE_SESSION_MODE=" .. session .. "\n")

-- nested_direct: love runs directly, no gamescope argv needed.
if session == "nested_direct" then
    os.exit(0)
end

-- ── Build gamescope argv ──────────────────────────────────────────────────

local out = gs.output or {}
local inn = gs.inner  or {}
local ow  = out.width   or 1920
local oh  = out.height  or 1080
local orr = out.refresh or 60
local iw  = inn.width   or ow
local ih  = inn.height  or oh

local parts = { "gamescope" }

-- drm_gamescope is always fullscreen; nested_gamescope respects display.fullscreen.
if session == "drm_gamescope" or gs.fullscreen ~= false then
    parts[#parts+1] = "-f"
end

parts[#parts+1] = "-W"; parts[#parts+1] = tostring(ow)
parts[#parts+1] = "-H"; parts[#parts+1] = tostring(oh)
parts[#parts+1] = "-w"; parts[#parts+1] = tostring(iw)
parts[#parts+1] = "-h"; parts[#parts+1] = tostring(ih)
parts[#parts+1] = "-r"; parts[#parts+1] = tostring(orr)

local filter = gs.filter
if filter then
    local scaler = gs.scaler or ((iw ~= ow or ih ~= oh) and "fit" or "auto")
    parts[#parts+1] = "-S"; parts[#parts+1] = scaler
    parts[#parts+1] = "-F"; parts[#parts+1] = filter
end

if gs.sharpness then
    parts[#parts+1] = "--sharpness"
    parts[#parts+1] = tostring(gs.sharpness)
end

if gs.hdr             then parts[#parts+1] = "--hdr-enabled"        end
if gs.adaptive_sync   then parts[#parts+1] = "--adaptive-sync"      end
if gs.force_grab      then parts[#parts+1] = "--force-grab-cursor"  end
if gs.expose_wayland  then parts[#parts+1] = "--expose-wayland"     end
if gs.composite_debug then parts[#parts+1] = "--composite-debug"    end
if gs.mangoapp        then parts[#parts+1] = "--mangoapp"           end

for _, flag in ipairs(gs.extra_flags or {}) do
    parts[#parts+1] = "'" .. tostring(flag):gsub("'", "'\\''") .. "'"
end

local argv = table.concat(parts, " ")
-- Wrap in single quotes for safe eval; escape any literal single quotes inside.
argv = argv:gsub("'", "'\\''")
io.write("GS_ARGS='" .. argv .. "'\n")
