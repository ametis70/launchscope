-- luacheck config for the launchscope UI (LÖVE2D / Lua 5.4)
std = "lua54"

-- LÖVE2D globals — love is mutable (callbacks are set by assigning to love.*)
globals = {
    "love",
    "newFont",
    "_init",
}

-- Ignore line length — stylua handles formatting
max_line_length = false

-- Third-party libs bundled in ui/lib
exclude_files = {
    "ui/lib/json.lua",
}

-- Unused arguments in callback stubs are intentional (API signatures must match)
unused_args = false
