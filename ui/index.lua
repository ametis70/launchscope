-- Top-level UI compositor.
--
-- Layers are defined as an ordered array. Each layer has:
--   draw()    renders the layer's content
--   active()  returns true when this layer has content to show
--
-- The compositor walks the layers, finds the highest active one, draws
-- one overlay at the end of (highest - 1), then draws all active layers
-- from that point up.
--
-- Overlay rule:
--   Layer 2 (aux) always draws but its overlay only shows when aux is focused.
--   All layers >= 3 always show their overlay when active.

local input = require("lib.input")
local shader = require("lib.shader")
local stack = require("components.modals.stack")
local T = require("lib.theme")

local info_bar = nil
local M = {}
local _view = nil
local _cfg = nil
local _ui = nil

function M.init(cfg, ui)
    _cfg = cfg
    _ui = ui
    info_bar = require("components.display.info_bar")
    info_bar.load(ui)
    local Launcher = require("views.launcher")
    _view = Launcher.new(_cfg, _ui)
    _view:load()
end

function M.update(dt)
    if _G.idle then
        _G.idle.update(dt)
    end
    -- During the wake grace period, skip UI updates so mouse hover logic
    -- cannot deactivate list focus before the user has a chance to interact.
    if _G.idle and _G.idle.isInputBlocked() then
        input.flush()
        if _G.cursor then
            _G.cursor.flush()
        end
        return
    end
    if not stack.isEmpty() then
        stack.update(input)
    else
        if _view and _view.update then
            _view:update(dt)
        end
    end
    input.flush()
    if _G.cursor then
        _G.cursor.flush()
    end
end

function M.draw()
    local modals = stack.all()
    local aux_focused = _view and _view.isAuxFocused and _view:isAuxFocused()
    local app_running = _view and _view.isRunning and _view:isRunning()

    -- Layer definitions. Order matters — lower index = lower in the stack.
    -- Each entry: { draw, active, overlay_when_focused_only }
    --   draw()                draws the layer content
    --   active()              true when this layer has something to show
    --   overlay_on_focus_only true means overlay only shows when THIS layer
    --                         is active but not because something above it is
    --                         (used for the aux menu dim)
    local layers = {
        {
            -- Layer 1: info bar + launch list
            draw = function()
                info_bar.draw()
                if _view then
                    _view:draw()
                end
            end,
            active = function()
                return true
            end,
        },
        {
            -- Layer 2: aux buttons (always drawn; overlay only when aux focused)
            draw = function()
                if _view then
                    _view:drawAux()
                end
            end,
            active = function()
                return true
            end,
            focus_overlay = function()
                return aux_focused
            end,
        },
        {
            -- Layer 3: running-app screen OR power modal
            draw = function()
                if app_running and _view then
                    _view:drawRunning()
                end
                if modals[1] then
                    modals[1]:draw()
                end
            end,
            active = function()
                return app_running or modals[1] ~= nil
            end,
        },
        {
            -- Layer 4: confirmation modal (second item on stack)
            draw = function()
                if modals[2] then
                    modals[2]:draw()
                end
            end,
            active = function()
                return modals[2] ~= nil
            end,
        },
    }

    -- Find the highest active layer index.
    local top = 1
    for i = #layers, 1, -1 do
        if layers[i].active() then
            top = i
            break
        end
    end

    -- Draw all layers. Insert one overlay before the topmost active layer,
    -- unless that layer uses focus_overlay (aux), in which case the overlay
    -- only appears when focus_overlay() is true.
    shader.draw()
    for i = 1, #layers do
        local layer = layers[i]
        if i == top and i > 1 then
            -- This is the topmost active layer — draw overlay before it.
            local fo = layer.focus_overlay
            if not fo or fo() then
                T.drawOverlay()
            end
        elseif i < top and layer.focus_overlay and layer.focus_overlay() then
            -- A lower layer wants its own focus overlay, but only when it IS
            -- the effective top (nothing above it active). Already handled above.
            -- No action needed here.
        end
        layer.draw()
    end

    -- Dim/blank overlay — always drawn last, on top of everything.
    if _G.idle then
        _G.idle.drawOverlay()
    end
end

function M.resize(w, h)
    if _view and _view.resize then
        _view:resize(w, h)
    end
end

function M.keypressed(key)
    local top = stack.top()
    if top and top.keypressed then
        top:keypressed(key)
    end
end

function M.pushModal(modal)
    stack.push(modal)
end
function M.popModal()
    stack.pop()
end

return M
