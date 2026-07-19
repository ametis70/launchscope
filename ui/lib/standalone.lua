-- Standalone process manager.
-- Launches apps locally with an optional gamescope wrapper, tracks the
-- running process, and reports when it exits — without quitting the UI.

local gamescope = require("lib.gamescope")
local M = {}

-- ── State ─────────────────────────────────────────────────────────────── --

local _pid = nil
local _app = nil
local _poll_timer = 0
local POLL_RATE = 0.5

M.on_exit = nil

-- ── Helpers ───────────────────────────────────────────────────────────── --

local function shellQuote(s)
    return "'" .. tostring(s):gsub("'", "'\\''") .. "'"
end

local function buildCmd(app)
    local gs = app.gamescope
    if not gs or gs.enabled == false then
        return app.exec
    end
    return gamescope.buildArgv(gs, app.exec)
end

-- ── Process management ────────────────────────────────────────────────── --

function M.launch(app)
    if _pid then
        return false, "an app is already running"
    end

    local cmd = buildCmd(app)
    local wrapped = "sh -c " .. shellQuote(cmd .. " & echo $!")
    local fh = io.popen(wrapped)
    if not fh then
        return false, "failed to spawn process"
    end

    local pid_str = fh:read("*l")
    fh:close()
    if not pid_str or pid_str == "" then
        return false, "failed to read PID after launch"
    end

    _pid = pid_str:match("^%s*(%d+)%s*$")
    if not _pid then
        return false, "unexpected PID output: " .. tostring(pid_str)
    end

    _app = app
    _poll_timer = 0
    return true, nil
end

function M.stop()
    if not _pid then
        return
    end
    os.execute("kill " .. _pid .. " 2>/dev/null")
end

function M.isRunning()
    return _pid ~= nil
end
function M.currentApp()
    return _app
end
function M.currentPid()
    return _pid
end

function M.update(dt)
    if not _pid then
        return
    end
    _poll_timer = _poll_timer + dt
    if _poll_timer < POLL_RATE then
        return
    end
    _poll_timer = 0

    local alive = os.execute("kill -0 " .. _pid .. " 2>/dev/null")
    if alive ~= 0 and alive ~= true then
        local old_app = _app
        _pid = nil
        _app = nil
        if M.on_exit then
            M.on_exit(old_app)
        end
    end
end

return M
