-- Cursor manager.
-- Loads custom hardware cursors from the pre-rasterised assets/icons/cursor-*.png
-- and provides a set(type) / flush() interface. The PNGs are scaled to the
-- configured cursor size at init time using nearest-neighbour interpolation.

local M = {}

local HOTSPOTS = {
    normal = { 0, 0 },
    pointer = { 5, 0 },
    text = { 11, 11 },
}

local PNG_FILES = {
    normal = "assets/icons/cursor-normal.png",
    pointer = "assets/icons/cursor-pointer.png",
    text = "assets/icons/cursor-text.png",
}

local PRIORITY = { normal = 1, pointer = 2, text = 3 }

local _cursors = {}
local _size = 24
local _current = nil -- last applied cursor type
local _pending = nil -- highest-priority request this frame
local _visible = true -- logical visibility (mouse vs gamepad mode)
local _dim_hidden = false -- true when hidden specifically because of dim/blank

local function loadCursor(name)
    local path = PNG_FILES[name]
    if not path then
        return nil
    end
    local ok, id = pcall(love.image.newImageData, path)
    if not ok then
        return nil
    end
    -- Scale to _size using nearest-neighbour for crisp pixel art.
    local src_w, src_h = id:getWidth(), id:getHeight()
    if src_w ~= _size or src_h ~= _size then
        local scaled = love.image.newImageData(_size, _size)
        scaled:mapPixel(function(x, y)
            local sx = math.floor(x * src_w / _size)
            local sy = math.floor(y * src_h / _size)
            return id:getPixel(sx, sy)
        end)
        id = scaled
    end
    local hs = HOTSPOTS[name] or { 0, 0 }
    local ok2, cur = pcall(love.mouse.newCursor, id, hs[1], hs[2])
    return ok2 and cur or nil
end

function M.init(size)
    _size = size or 24
    _cursors = {}
    for name in pairs(PNG_FILES) do
        local cur = loadCursor(name)
        _cursors[name] = cur or false
        if not cur then
            print("INFO cursors: " .. name .. " — using system cursor")
        end
    end
    _current = nil
    _pending = "normal"
    _visible = true
    M.flush()
end

-- Request a cursor type this frame. Higher-priority requests win.
function M.set(type)
    if not _visible then
        return
    end
    local p_new = PRIORITY[type] or 0
    local p_cur = PRIORITY[_pending] or 0
    if p_new > p_cur then
        _pending = type
    end
end

-- Apply the winning cursor for this frame. Call once per frame after all
-- component updates.
function M.flush()
    local want = _visible and (_pending or "normal") or nil
    _pending = "normal" -- reset for next frame
    if want == _current then
        return
    end
    _current = want
    if want then
        local cur = _cursors[want]
        if cur then
            love.mouse.setCursor(cur)
        else
            love.mouse.setCursor() -- system default
        end
    else
        love.mouse.setCursor() -- system default when hidden
    end
end

-- hide: called when keyboard/gamepad input is detected.
-- Swaps to the system cursor (invisible in fullscreen gamescope, but
-- avoids suppressing it entirely on Wayland with setVisible(false)).
function M.hide()
    if not _visible then
        return
    end
    _visible = false
    _dim_hidden = false
    _current = nil
    M.flush()
end

-- hideDim: called when the idle dim overlay activates.
-- Hides the cursor until the user moves or clicks the mouse.
function M.hideDim()
    if _dim_hidden then
        return
    end
    _dim_hidden = true
    _visible = false
    _current = nil
    M.flush()
end

-- showDim: called when the mouse moves or is clicked while dim-hidden.
-- Restores the cursor and clears the dim-hidden flag.
function M.showDim()
    if not _dim_hidden then
        return
    end
    _dim_hidden = false
    _visible = true
    _current = nil
end

-- isHiddenByDim: returns true when the cursor is hidden due to dimming.
-- Used by main.lua to swallow mouse clicks that are only waking the cursor.
function M.isHiddenByDim()
    return _dim_hidden
end

-- show: called when mouse movement is detected.
function M.show()
    if _visible then
        return
    end
    _visible = true
    _current = nil -- force re-apply on next flush
end

return M
