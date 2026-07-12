-- Modal stack manager.
-- A LIFO stack of modal instances. While the stack is non-empty, the active
-- view receives no input — only the topmost modal does.
--
-- Each modal must implement:
--   modal:update(inp)   → (called only when topmost)
--   modal:draw()        → (called for all modals, bottom-up)
--
-- Usage (from index.lua):
--   local stack = require("components.modals.stack")
--   stack.push(modal)
--   stack.pop()
--   stack.update(inp)    -- routes to topmost only
--   stack.draw()         -- draws all, bottom-up
--   stack.isEmpty()      -- bool

local M = {}

local _stack = {}

function M.push(modal)
    _stack[#_stack + 1] = modal
end

function M.pop()
    if #_stack > 0 then
        _stack[#_stack] = nil
    end
end

function M.isEmpty()
    return #_stack == 0
end

function M.top()
    return _stack[#_stack]
end

-- Returns the full stack as an ordered list (index 1 = bottom, last = top).
function M.all()
    local t = {}
    for i = 1, #_stack do t[i] = _stack[i] end
    return t
end

-- Route input to the topmost modal.
-- The modal is responsible for calling index.popModal() (via on_close) when done.
function M.update(inp)
    local top = _stack[#_stack]
    if top then top:update(inp) end
end

-- Draw all modals bottom-up (topmost last, on top).
-- No overlay is drawn here — index.draw() inserts overlays between layers.
function M.draw()
    for i = 1, #_stack do
        _stack[i]:draw()
    end
end

-- Clear the entire stack (used on view switches to avoid stale modals).
function M.clear()
    _stack = {}
end

return M
