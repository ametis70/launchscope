-- Launcher view.
-- App list + aux buttons (Power, Close App).
-- Uses components/interactive/list.lua and components/interactive/button.lua.
-- Power → pushes PowerModal onto the modal stack.

local List       = require("components.interactive.list")
local Button     = require("components.interactive.button")
local PowerModal   = require("components.modals.power_modal")
local ConfirmModal = require("components.modals.confirm_modal")
local SoundModal   = require("components.modals.sound_modal")
local client     = require("lib.client")
local standalone = require("lib.standalone")
local input      = require("lib.input")
local icons      = require("lib.icons")
local json       = require("lib.json")
local T          = require("lib.theme")

local Launcher = {}
Launcher.__index = Launcher

-- ── Standalone apps loader ─────────────────────────────────────────────── --

local function loadStandaloneApps()
    local uicfg = require("lib.uiconfig")
    local dir   = uicfg.configDir()

    local function readJSON(path)
        local fh = io.open(path, "r")
        if not fh then return nil end
        local raw = fh:read("*a"); fh:close()
        local ok, data = pcall(json.decode, raw)
        return ok and data or nil
    end

    local apps = readJSON(dir .. "/apps.json") or {}
    local over  = readJSON(dir .. "/apps.override.json")
    if over then
        local byId = {}
        for _, a in ipairs(apps) do byId[a.id] = a end
        for _, a in ipairs(over)  do byId[a.id] = a end
        apps = {}
        for _, a in pairs(byId) do apps[#apps+1] = a end
        table.sort(apps, function(a, b) return a.id < b.id end)
    end
    return apps
end

-- ── Constructor ───────────────────────────────────────────────────────── --

function Launcher.new(cfg, ui)
    local self = setmetatable({}, Launcher)
    self.cfg        = cfg
    self.ui         = ui
    self.process_mode = cfg.process_mode or "daemon"
    self.font       = newFont(T.FONT_LG)
    self.font_small = newFont(T.FONT_UI)

    self.list_state  = "loading"
    self.list_error  = nil
    self.list        = nil
    self.apps        = {}

    self.focus_menu  = "launch"
    self.aux_idx     = 1
    self.poll_timer  = 0
    self.poll_rate   = 1.0
    self.retry_timer = 0
    self.retry_rate  = 3.0   -- retry server connection every 3s while in error
    self._server_app_running = false
    self._close_btn = nil

    self._aux_buttons = {}  -- built in _buildAux()

    standalone.on_exit = function()
        self._close_btn = nil
        self:_reload()
    end

    return self
end

function Launcher:load()
    self:_reload()
end

-- State queries for index.draw() layer composition.
function Launcher:isAuxFocused()
    return self.focus_menu == "aux" and input.device() ~= "mouse"
end

function Launcher:isRunning()
    return self.process_mode == "standalone" and standalone.isRunning()
end

function Launcher:resize(w, h)
    self._aux_def_key = nil   -- force aux reposition at new window width
    self._close_btn   = nil   -- force close button reposition
    if self.list_state == "ready" then self:_buildList() end
    self:_buildAux()
end

-- ── Update ────────────────────────────────────────────────────────────── --

function Launcher:update(dt)
    if self.process_mode == "standalone" then
        standalone.update(dt)
        if standalone.isRunning() then
            -- While an app is running, only handle the centre close button.
            self:_updateRunning()
            return
        end
        -- App just exited — clear the centre close button.
        self._close_btn = nil
    end

    if self.process_mode == "daemon" then
        self.poll_timer = self.poll_timer + dt
        if self.poll_timer >= self.poll_rate then
            self.poll_timer = 0
            self:_pollStatus()
        end

        -- Retry connecting to the server while in error state.
        if self.list_state == "error" then
            self.retry_timer = self.retry_timer + dt
            if self.retry_timer >= self.retry_rate then
                self.retry_timer = 0
                self:_reload()
            end
        else
            self.retry_timer = 0
        end
    end

    local inp = input
    self:_buildAux()  -- rebuild each frame so Close App appears/disappears dynamically

    -- Update all aux buttons (hover + click).
    for _, btn in ipairs(self._aux_buttons) do
        btn:update(inp)
    end

    -- Focus routing.
    -- Mouse: focus_menu follows hover state entirely.
    -- Keyboard/gamepad: focus_menu is the sole authority.
    if inp.device() == "mouse" then
        local any_hover = false
        for i, btn in ipairs(self._aux_buttons) do
            if btn.focused then
                self.focus_menu = "aux"
                self.aux_idx    = i
                any_hover       = true
                if self.list then self.list.active = false end
                break
            end
        end
        if not any_hover and self.focus_menu == "aux" then
            self.focus_menu = "launch"
            if self.list then self.list.active = true end
        end
    end

    if self.focus_menu == "launch" then
        self:_updateLaunch(inp, dt)
    else
        -- For mouse, _updateAux only handles keyboard nav (SELECT already fired in btn:update).
        self:_updateAux(inp, inp.device() == "mouse")
    end

    -- Global hotkeys.
    if inp.wasPressed("POWER") then
        _G.index.pushModal(PowerModal.new(self.ui, { process_mode = self.process_mode }))
    end

    if inp.wasPressed("VOLUME_UP") then
        local res = client.setVolume(0.05)
        if res then _G.volumeBar.notifyChange(res.volume, res.muted) end
    end
    if inp.wasPressed("VOLUME_DOWN") then
        local res = client.setVolume(-0.05)
        if res then _G.volumeBar.notifyChange(res.volume, res.muted) end
    end
end

function Launcher:_updateLaunch(inp, dt)
    if inp.wasPressed("LEFT") then
        self.focus_menu = "aux"
        self.aux_idx    = #self._aux_buttons
        if self.list then self.list.active = false end
        if _G.sound then _G.sound.navigate() end
        return
    end
    if inp.wasPressed("RIGHT") then
        self.focus_menu = "aux"
        self.aux_idx    = 1
        if self.list then self.list.active = false end
        if _G.sound then _G.sound.navigate() end
        return
    end
    if self.list_state == "ready" and self.list then
        self.list:update(dt, inp)
    end
end

-- Called each frame while a standalone app is running.
function Launcher:_updateRunning()
    local inp = input
    local sw, sh = love.graphics.getDimensions()
    local ui  = self.ui

    -- Build/reposition close button if needed.
    if not self._close_btn then
        self._close_btn = Button.new({ icon = "close", label = "Close App", ui = ui })
    end
    local btn     = self._close_btn
    local name_h  = self.font:getHeight()
    local pid_h   = self.font_small:getHeight()
    local gap1    = ui.padding        -- name → pid
    local gap2    = ui.padding * 2    -- pid → button
    local bw      = btn:width()
    local bh      = btn:height()
    local block_h = name_h + gap1 + pid_h + gap2 + bh
    local block_y = math.floor((sh - block_h) / 2)
    local btn_y   = block_y + name_h + gap1 + pid_h + gap2
    btn:setPos(math.floor((sw - bw) / 2), btn_y)

    -- Button is always focused — it's the only interactive item.
    btn.focused = true

    -- Mouse: only set cursor, don't change focus.
    if inp.device() == "mouse" then
        local mx, my = inp.mouseX(), inp.mouseY()
        local over   = require("lib.hittest")(mx, my, btn:rect())
        if _G.cursor then _G.cursor.set(over and "pointer" or "normal") end
        if over and inp.wasPressed("SELECT") then
            self:_confirmClose()
        end
    else
        if inp.wasPressed("SELECT") or inp.wasPressed("BACK") then
            self:_confirmClose()
        end
    end
end

function Launcher:_confirmClose()
    local app  = standalone.currentApp()
    local name = app and app.name or "App"
    _G.index.pushModal(ConfirmModal.new(
        "Close App",
        "Close " .. name .. "?",
        function() self:_closeApp() end,
        self.ui
    ))
end

function Launcher:_updateAux(inp, skip_select)
    -- BACK or UP/DOWN returns to the launch list.
    if inp.wasPressed("BACK") or inp.wasPressed("UP") or inp.wasPressed("DOWN") then
        self.focus_menu = "launch"
        for _, btn in ipairs(self._aux_buttons) do btn.focused = false end
        if self.list then self.list.active = true end
        if _G.sound then _G.sound.navigate() end
        return
    end

    local n = #self._aux_buttons
    if n == 0 then return end

    if inp.wasPressed("LEFT") then
        self.aux_idx = self.aux_idx - 1
        if self.aux_idx < 1 then self.aux_idx = n end
        if _G.sound then _G.sound.navigate() end
    elseif inp.wasPressed("RIGHT") then
        self.aux_idx = self.aux_idx + 1
        if self.aux_idx > n then self.aux_idx = 1 end
        if _G.sound then _G.sound.navigate() end
    end
    self.aux_idx = math.max(1, math.min(self.aux_idx, n))

    -- Sync button focused states.
    for i, btn in ipairs(self._aux_buttons) do
        btn.focused = (i == self.aux_idx)
    end

    -- SELECT: keyboard/gamepad only — mouse clicks are handled in btn:update.
    if not skip_select and inp.wasPressed("SELECT") then
        local btn = self._aux_buttons[self.aux_idx]
        if btn and btn.on_select then
            if _G.sound then _G.sound.select() end
            btn.on_select()
        end
    end
end

-- ── Draw ──────────────────────────────────────────────────────────────── --

-- drawBase: layer 1 content — launch list only.
function Launcher:draw()
    local sw, sh = love.graphics.getDimensions()
    self:_drawList(sw, sh)
end

-- drawAux: layer 2 content — aux buttons (and running-app overlay content).
-- Called by index.draw() after the layer-1 overlay.
function Launcher:drawAux()
    self:_drawAuxButtons()
end

-- drawRunning: layer 2 running-app content (name, pid, close button).
-- Called by index.draw() after the layer-1 overlay.
function Launcher:drawRunning()
    local sw, sh = love.graphics.getDimensions()
    self:_drawRunning(sw, sh)
end

function Launcher:_drawList(sw, sh)
    local ui = self.ui
    if self.list_state == "loading" then
        love.graphics.setFont(self.font_small)
        love.graphics.setColor(T.DIM)
        love.graphics.printf("Loading…", 0, sh / 2, sw, "center")
        love.graphics.setColor(1, 1, 1, 1)

    elseif self.list_state == "error" then
        love.graphics.setFont(self.font_small)
        love.graphics.setColor(T.ERROR)
        love.graphics.printf(self.list_error or "Failed to load apps",
            ui.corner_padding, sh / 2 - ui.font_size,
            sw - ui.corner_padding * 2, "center")
        -- Retrying hint
        if self.process_mode == "daemon" then
            love.graphics.setColor(T.DIM)
            love.graphics.printf("Retrying in " .. math.ceil(self.retry_rate - self.retry_timer) .. "s…",
                ui.corner_padding, sh / 2,
                sw - ui.corner_padding * 2, "center")
        end
        love.graphics.setColor(1, 1, 1, 1)

    elseif self.list_state == "ready" then
        if not (self.process_mode == "standalone" and standalone.isRunning()) then
            if self.list then self.list:draw() end
        end
    end
end

function Launcher:_drawRunning(sw, sh)
    local ui   = self.ui
    local app  = standalone.currentApp()
    local pid  = standalone.currentPid()
    local name = app and app.name or "App"

    local name_h  = self.font:getHeight()
    local pid_h   = self.font_small:getHeight()
    local gap1    = ui.padding        -- name → pid
    local gap2    = ui.padding * 2    -- pid → button
    local bh      = self._close_btn and self._close_btn:height() or 0
    local block_h = name_h + gap1 + pid_h + gap2 + bh
    local block_y = math.floor((sh - block_h) / 2)

    -- Name
    love.graphics.setFont(self.font)
    love.graphics.setColor(T.TEXT)
    love.graphics.printf(name .. " is running", 0, block_y, sw, "center")

    -- PID (smaller, dimmed)
    love.graphics.setFont(self.font_small)
    love.graphics.setColor(T.TEXT_DIM)
    love.graphics.printf("PID: " .. (pid or "?"), 0, block_y + name_h + gap1, sw, "center")

    -- Close button
    if self._close_btn then self._close_btn:draw() end

    love.graphics.setColor(1, 1, 1, 1)
end

function Launcher:_drawAuxButtons()
    for _, btn in ipairs(self._aux_buttons) do
        btn:draw()
    end
end

-- ── Private: build helpers ─────────────────────────────────────────────── --

function Launcher:_buildAux()
    local ui       = self.ui
    local sw, _sh  = love.graphics.getDimensions()
    local show_close =
        (self.process_mode == "standalone" and standalone.isRunning()) or
        (self.process_mode == "daemon" and self._server_app_running)

    local defs = {}
    if show_close then
        defs[#defs+1] = { icon = "close",  label = "Close", id = "close_app" }
    end
    defs[#defs+1] = { icon = "volume", label = "Sound", id = "sound" }
    defs[#defs+1] = { icon = "power",  label = "Power", id = "power"  }

    -- Rebuild when composition OR window width changes.
    local key = sw .. ":" .. #defs
    if self._aux_def_key == key then return end
    self._aux_def_key = key

    local gap = math.floor(ui.font_size * 0.5)
    local y   = ui.corner_padding
    local x   = sw - ui.corner_padding

    self._aux_buttons = {}
    for i = #defs, 1, -1 do
        local d   = defs[i]
        local btn = Button.new({ icon = d.icon, label = d.label, ui = ui })
        x = x - btn:width()
        btn:setPos(x, y)
        x = x - gap

        local id = d.id
        btn.on_select = function()
            if id == "power" then
                _G.index.pushModal(PowerModal.new(self.ui, { process_mode = self.process_mode }))
            end
            if id == "sound"    then _G.index.pushModal(SoundModal.new(self.ui)) end
            if id == "close_app" then self:_closeApp() end
        end

        table.insert(self._aux_buttons, 1, btn)
    end
end

function Launcher:_buildList()
    local sw, sh = love.graphics.getDimensions()
    local ui     = self.ui

    local list_w  = math.floor(sw * 0.6)
    local list_x  = math.floor((sw - list_w) / 2)
    local arrow_h = math.floor(ui.item_height * 0.6)

    local available_h = sh - arrow_h * 2
    local n           = #self.apps
    local max_vis     = math.max(1, math.floor(available_h * 0.5 / ui.item_height))
    local vis         = math.min(n, max_vis)
    local list_h      = vis * ui.item_height
    local list_y      = math.floor((sh - list_h) / 2)

    local pad_x  = math.floor(ui.font_size * 1.2)
    local max_tw = 0
    for _, a in ipairs(self.apps) do
        local tw = self.font:getWidth(a.name or "")
        if tw > max_tw then max_tw = tw end
    end
    local item_w = max_tw + pad_x * 2

    local items = {}
    for _, a in ipairs(self.apps) do
        items[#items+1] = { id = a.id, label = a.name }
    end

    local prev = self.list and self.list.focused or 1
    self.list = List.new(items, {
        x         = list_x,
        y         = list_y,
        width     = list_w,
        item_w    = item_w,
        height    = list_h,
        ui        = ui,
        font      = self.font,
        on_select = function(item) self:_launchApp(item.id) end,
    })
    self.list.focused = math.min(prev, math.max(1, n))
    self.list:_clampOffset()
end

-- ── Private: app management ───────────────────────────────────────────── --

function Launcher:_reload()
    self.list_state = "loading"
    self.list       = nil

    if self.process_mode == "standalone" then
        local ok, apps = pcall(loadStandaloneApps)
        if ok and apps then
            self.apps       = apps
            self.list_state = "ready"
            self:_buildList()
        else
            self.list_state = "error"
            self.list_error = "Failed to load apps.json"
        end
    else
        local apps, err = client.getApps()
        if apps then
            self.apps       = apps
            self.list_state = "ready"
            self:_buildList()
        else
            self.list_state = "error"
            self.list_error = "Server unavailable: " .. tostring(err)
        end
    end

    self:_buildAux()
end

function Launcher:_launchApp(id)
    if self.process_mode == "standalone" then
        local app = nil
        for _, a in ipairs(self.apps) do
            if a.id == id then app = a; break end
        end
        if not app then return end
        local ok, err = standalone.launch(app)
        if not ok then
            print("ERROR: failed to launch " .. id .. ": " .. tostring(err))
        end
    else
        client.launch(id)
        love.event.quit()
    end
end

function Launcher:_closeApp()
    if self.process_mode == "standalone" then
        standalone.stop()
    else
        client.stop()
    end
end

function Launcher:_pollStatus()
    local status = client.getStatus()
    if status then
        if status.audio then
            _G.volumeBar.syncState(status.audio.volume, status.audio.muted)
        end
        self._server_app_running = (status.state == "app_running")
    end
end

return Launcher
