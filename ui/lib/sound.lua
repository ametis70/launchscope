-- UI sound manager.
-- Plays navigation and selection sounds using the two bundled wav files.
-- Volume is controlled independently from system volume.
--
-- Public API:
--   sound.load(ui_volume)   call once from _init(); ui_volume 0.0–1.0
--   sound.navigate()        play the navigation sound (move between items)
--   sound.select()          play the selection sound (confirm/enter)
--   sound.setVolume(v)      set UI volume 0.0–1.0 at runtime

local M = {}

local _navigate = nil -- love.Source
local _select = nil -- love.Source
local _volume = 1.0

local function loadSource(path)
    local ok, src = pcall(love.audio.newSource, path, "static")
    if not ok then
        print("WARNING sound: failed to load " .. path .. ": " .. tostring(src))
        return nil
    end
    return src
end

function M.load(ui_volume)
    _volume = ui_volume or 1.0
    _navigate = loadSource("assets/sound/Abstract1.wav")
    _select = loadSource("assets/sound/Abstract2.wav")
    M.setVolume(_volume)

    -- Pre-warm the audio backend: play both sources at volume 0 so the
    -- audio device is already active when the first real play() fires.
    -- Without this, the first sound has a ~100ms stutter on cold start.
    for _, src in ipairs({ _navigate, _select }) do
        if src then
            src:setVolume(0)
            src:play()
            src:stop()
            src:seek(0)
        end
    end
    M.setVolume(_volume)
end

function M.setVolume(v)
    _volume = math.max(0.0, math.min(1.0, v))
    if _navigate then
        _navigate:setVolume(_volume)
    end
    if _select then
        _select:setVolume(_volume)
    end
end

function M.getVolume()
    return _volume
end

local function play(src)
    if not src or _volume == 0 then
        return
    end
    -- Stop and rewind so rapid navigation doesn't queue up.
    src:stop()
    src:seek(0)
    src:play()
end

function M.navigate()
    play(_navigate)
end
function M.select()
    play(_select)
end

return M
