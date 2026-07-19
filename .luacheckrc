-- luacheck config for the launchscope UI (LÖVE2D / Lua 5.4)
std = "lua54"

-- LÖVE2D globals
read_globals = {
    "love",
}

-- Launchscope globals set in main.lua
globals = {
    "_G",
    "newFont",
}

-- Ignore line length — stylua handles formatting
max_line_length = false

-- Third-party libs bundled in ui/lib
ignore = {
    "lib/json.lua",
}
