-- conf.lua — LÖVE window configuration
--
-- Reads LAUNCHSCOPE_SESSION_MODE (set by the shell wrapper or operator) to
-- determine whether to open a desktop window or run fullscreen.
--
--   drm_gamescope    — gamescope owns the display via KMS/DRM; always fullscreen
--   nested_gamescope — gamescope runs inside an existing compositor
--   nested_direct    — love runs directly inside an existing compositor
--
-- In nested_gamescope and nested_direct modes, display.fullscreen from config
-- controls whether the LÖVE window is fullscreen or windowed. The wrapper
-- script (gamescope-args.lua) sets LAUNCHSCOPE_SESSION_MODE before exec'ing love.
--
-- Optional overrides (nested modes only):
--   LAUNCHSCOPE_WIDTH=N    Window width  (default: 1280)
--   LAUNCHSCOPE_HEIGHT=N   Window height (default: 720)

function love.conf(t)
    t.window.title = "Launchscope"
    t.console      = false

    t.modules.audio   = true
    t.modules.sound   = true
    t.modules.video   = false
    t.modules.touch   = false
    t.modules.physics = false

    t.modules.joystick = true
    t.modules.keyboard = true
    t.modules.mouse    = true

    local session = os.getenv("LAUNCHSCOPE_SESSION_MODE") or "drm_gamescope"
    local nested  = (session == "nested_gamescope" or session == "nested_direct")

    if nested then
        local w = tonumber(os.getenv("LAUNCHSCOPE_WIDTH"))  or 1280
        local h = tonumber(os.getenv("LAUNCHSCOPE_HEIGHT")) or 720
        t.window.width          = w
        t.window.height         = h
        t.window.fullscreen     = false
        t.window.fullscreentype = "desktop"
        t.window.resizable      = true
        t.window.borderless     = false
        t.window.vsync          = 1
    else
        -- drm_gamescope: gamescope owns the display, always fullscreen
        t.window.fullscreen     = true
        t.window.fullscreentype = "desktop"
        t.window.borderless     = true
        t.window.vsync          = 1
    end
end
