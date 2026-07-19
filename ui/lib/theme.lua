-- Shared colour palette and text-size scale.
-- All components read colours and font sizes from here.
--
-- Colours are RGBA tables { r, g, b, a }.
-- Font sizes are integer pixel values set by T.init(ui) at startup.

local T = {}

-- ── Text ──────────────────────────────────────────────────────────────── --
T.TEXT = { 1, 1, 1, 0.90 }
T.TEXT_DIM = { 1, 1, 1, 0.65 }
T.TEXT_MUTED = { 1, 1, 1, 0.45 }

-- ── Interactive elements ───────────────────────────────────────────────── --
T.BTN_NORMAL = { 1, 1, 1, 0.55 }
T.BTN_FOCUSED = { 1, 1, 1, 1.00 }
T.BTN_BG = { 1, 1, 1, 0.08 }

T.ROW_LABEL = { 1, 1, 1, 0.65 }
T.ROW_VALUE = { 1, 1, 1, 1.00 }
T.ROW_FOCUS_BG = { 1, 1, 1, 0.08 }

T.SECTION = { 0.5, 0.8, 1.0, 1.00 }

-- ── Tabs ──────────────────────────────────────────────────────────────── --
T.TAB_ACTIVE = { 1, 1, 1, 1.00 }
T.TAB_INACTIVE = { 1, 1, 1, 0.40 }
T.TAB_BG = { 1, 1, 1, 0.06 }
T.TAB_LINE = { 0.3, 0.6, 1.0, 0.90 }

-- ── Modals ────────────────────────────────────────────────────────────── --
T.OVERLAY = { 0, 0, 0, 0.55 }
T.PANEL = { 0.08, 0.08, 0.12, 0.93 }
T.PANEL_BORDER = { 1, 1, 1, 0.08 }

-- Draw a full-screen dim overlay using T.OVERLAY.
-- Call this whenever a layer needs to visually recede.
function T.drawOverlay()
    local sw, sh = love.graphics.getDimensions()
    love.graphics.setColor(T.OVERLAY)
    love.graphics.rectangle("fill", 0, 0, sw, sh)
    love.graphics.setColor(1, 1, 1, 1)
end

T.MODAL_TITLE = { 1, 1, 1, 0.90 }
T.CLOSE_NORMAL = { 1, 1, 1, 0.55 }
T.CLOSE_FOCUSED = { 1, 1, 1, 1.00 }
T.CLOSE_BG = { 1, 1, 1, 0.10 }

-- ── Status ────────────────────────────────────────────────────────────── --
T.STATUS_OK = { 0.3, 0.9, 0.4, 1.00 }
T.STATUS_ERR = { 1.0, 0.4, 0.4, 1.00 }
T.NOTE = { 1, 0.8, 0.4, 0.85 }

-- ── Misc ──────────────────────────────────────────────────────────────── --
T.PILL_BG = { 1, 1, 1, 0.08 }
T.EDIT_BG = { 0.1, 0.1, 0.2, 0.95 }
T.ERROR = { 1, 0.4, 0.4, 1.00 }
T.DIM = { 1, 1, 1, 0.40 }
T.SAVE = { 0.2, 0.7, 0.3, 1.00 }
T.BACK_BTN = { 0.5, 0.5, 0.5, 0.80 }

-- ── Font sizes ────────────────────────────────────────────────────────── --
-- Populated by T.init(ui) in main.lua after _G.UI is built.
-- All components use these instead of computing multipliers inline.
--
-- T.FONT_LG  full base size  — launcher app list (the primary interactive target)
-- T.FONT_UI  75% of base     — everything else: header, buttons, info bar, modal text
T.FONT_LG = 32
T.FONT_UI = 24

-- Horizontal padding inside pill-shaped elements (info bar pills, row focus
-- backgrounds). Extracted so all components stay visually consistent.
T.ROW_PAD_H = 19 -- math.floor(38 * 0.5) at scale 1.0

-- init must be called once from main.lua after _G.UI is constructed.
-- It recomputes all font size values from ui.font_size so that scale
-- changes (cfg.scale) are reflected correctly.
function T.init(ui)
    local scale = ui.font_size / 38
    T.FONT_LG = math.floor(32 * scale)
    T.FONT_UI = math.floor(24 * scale)
    T.ROW_PAD_H = math.floor(ui.font_size * 0.5)
end

return T
