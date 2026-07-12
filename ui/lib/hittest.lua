-- Rect hit-test utility.
-- A tiny helper used by all interactive components to check mouse position.
--
-- Usage:
--   local hit = require("lib.hittest")
--   if hit(mx, my, {x, y, w, h}) then ... end

local function hit(mx, my, r)
    return mx >= r[1] and mx < r[1] + r[3]
       and my >= r[2] and my < r[2] + r[4]
end

return hit
